require 'rails_helper'

describe Waha::IncomingMessageService do
  self.use_transactional_tests = false

  around do |example|
    clean_database!
    example.run
  ensure
    clean_database!
  end

  let(:channel) { create(:channel_waha, groups_enabled: true) }
  let(:inbox) { channel.inbox }

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  # rubocop:disable Metrics/ParameterLists
  def build_payload(stanza:, chat_jid: '5511888888888@c.us', from_me: false, participant: nil, reply_to: nil, timestamp: nil)
    payload = {
      'id' => "#{from_me ? 'true' : 'false'}_#{chat_jid}_#{stanza}",
      'body' => "message #{stanza}",
      'from' => chat_jid,
      'to' => '5511999999999@c.us',
      'fromMe' => from_me,
      'type' => 'chat',
      'hasMedia' => false,
      '_data' => { 'Info' => { 'Chat' => chat_jid, 'PushName' => 'John Doe' } }
    }
    payload['participant'] = participant if participant
    payload['replyTo'] = reply_to if reply_to
    payload['timestamp'] = timestamp if timestamp
    payload
  end
  # rubocop:enable Metrics/ParameterLists

  def perform(payload, channel_instance = channel)
    described_class.new(channel: channel_instance, payload: payload).perform
  end

  def clean_database!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.disable_referential_integrity do
        (connection.tables - %w[schema_migrations ar_internal_metadata]).each do |table|
          connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
        end
      end
    end
  end

  describe 'a duplicate delivery of the same event' do
    it 'does not mirror the message twice when the twin lands during the media download' do
      payload = build_payload(stanza: 'AAA111')
      twin_landed = false

      allow_any_instance_of(Waha::MessageConverters::Text).to receive(:download) do # rubocop:disable RSpec/AnyInstance
        unless twin_landed
          twin_landed = true
          perform(build_payload(stanza: 'AAA111'))
        end
        nil
      end

      perform(payload)

      expect(twin_landed).to be(true)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
      expect(WahaMessageMapping.where(chat_jid: '5511888888888@c.us', external_id: 'AAA111').count).to eq(1)
    end
  end

  describe 'a burst from a contact with no conversation yet' do
    it 'takes the contact_inbox lock before reading, and reuses what the winner created' do
      competitor = nil

      allow_any_instance_of(ContactInbox).to receive(:lock!).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
        if competitor.nil?
          contact_inbox = ContactInbox.find_by!(inbox_id: inbox.id)
          competitor = create(:conversation, account: channel.account, inbox: inbox,
                                             contact: contact_inbox.contact, contact_inbox: contact_inbox)
        end
        original.call
      end

      perform(build_payload(stanza: 'AAA111'))

      expect(competitor).to be_present
      expect(Conversation.where(inbox_id: inbox.id).count).to eq(1)
      expect(inbox.messages.last.conversation_id).to eq(competitor.id)
    end
  end

  describe 'real concurrent webhook delivery for the same message' do
    it 'converges to exactly one message, one mapping, and returns the persisted message to both threads' do
      payload = build_payload(stanza: 'RACE100')
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ch = Channel::Waha.find(channel.id)
            barrier.wait
            results << described_class.new(channel: ch, payload: payload).perform
          end
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)

      expect(errors).to be_empty
      expect(results.size).to eq(2)
      expect(results.map(&:id).uniq.size).to eq(1)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
      expect(WahaMessageMapping.where(channel: channel, external_id: 'RACE100').count).to eq(1)
      expect(Conversation.where(inbox_id: inbox.id).count).to eq(1)
    end
  end

  describe 'race between live webhook and history import for the same message' do
    it 'converges to one message and one mapping regardless of which finishes first' do
      payload = build_payload(stanza: 'HISTRACE1', timestamp: 1.hour.ago.to_i)
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      contact = create(:contact, account: channel.account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us')
      conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      t1 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ch = Channel::Waha.find(channel.id)
          barrier.wait
          results << described_class.new(channel: ch, payload: payload).perform
        end
      rescue StandardError => e
        errors << e
      end

      t2 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ch = Channel::Waha.find(channel.id)
          conv = Conversation.find(conversation.id)
          barrier.wait
          results << Waha::HistoryMessageWriter.new(
            channel: ch, payload: payload, conversation: conv, kind: 'gap_fill'
          ).perform
        end
      rescue StandardError => e
        errors << e
      end

      [t1, t2].each(&:join)

      expect(errors).to be_empty
      expect(results.size).to eq(2)
      expect(results.map(&:id).uniq.size).to eq(1)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
      expect(WahaMessageMapping.where(channel: channel, external_id: 'HISTRACE1').count).to eq(1)
      expect(Conversation.where(inbox_id: inbox.id).count).to eq(1)
    end
  end

  describe 'database unique constraint rollback on concurrent collision' do
    it 'rolls back the losing transaction without leaving a phantom message, returning the winner' do
      other_message = create(:message, account: channel.account, inbox: inbox, source_id: 'unrelated_other')
      WahaMessageMapping.create!(
        channel: channel, message: other_message, chat_jid: '5511888888888@c.us',
        external_id: 'DBRACE1', direction: :incoming
      )

      payload = build_payload(stanza: 'DBRACE1')
      result = described_class.new(channel: channel, payload: payload).perform

      expect(result).to eq(other_message)
      expect(inbox.messages.where(source_id: payload['id'])).to be_empty
      expect(WahaMessageMapping.where(chat_jid: '5511888888888@c.us', external_id: 'DBRACE1').count).to eq(1)
    end
  end

  describe 'different chats with the same external stanza id' do
    it 'does not falsely discard or cross-associate messages across different chats' do
      chat1 = '5511888888888@c.us'
      chat2 = '5511999999999@c.us'
      stanza = 'COMMON1'

      payload1 = build_payload(stanza: stanza, chat_jid: chat1)
      payload2 = build_payload(stanza: stanza, chat_jid: chat2)

      msg1 = perform(payload1)
      msg2 = perform(payload2)

      expect(msg1).to be_persisted
      expect(msg2).to be_persisted
      expect(msg1.id).not_to eq(msg2.id)
      expect(msg1.conversation_id).not_to eq(msg2.conversation_id)

      expect(WahaMessageMapping.where(channel: channel, external_id: stanza).count).to eq(2)
      expect(WahaMessageMapping.find_by(channel: channel, chat_jid: chat1, external_id: stanza).message_id).to eq(msg1.id)
      expect(WahaMessageMapping.find_by(channel: channel, chat_jid: chat2, external_id: stanza).message_id).to eq(msg2.id)
    end
  end

  describe 'preserving group sender metadata on deduplication' do
    it 'preserves structured participant info on message and mapping and does not duplicate on re-delivery' do
      group_jid = '120363000000000000@g.us'
      participant = '5511777777777@c.us'
      payload = build_payload(stanza: 'GRPMSG1', chat_jid: group_jid, participant: participant)

      msg1 = perform(payload)
      msg2 = perform(payload)

      expect(msg1.id).to eq(msg2.id)
      expect(msg1.content_attributes['participant_jid']).to eq(participant)
      mapping = WahaMessageMapping.find_by!(channel: channel, chat_jid: group_jid, external_id: 'GRPMSG1')
      expect(mapping.participant_jid).to eq(participant)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
    end
  end

  describe 'preserving reply context on deduplication' do
    it 'preserves in_reply_to link to quoted message and does not duplicate on re-delivery' do
      quoted = perform(build_payload(stanza: 'QUOTED1'))
      reply_payload = build_payload(stanza: 'REPLY1', reply_to: { 'id' => 'QUOTED1' })

      reply1 = perform(reply_payload)
      reply2 = perform(reply_payload)

      expect(reply1.id).to eq(reply2.id)
      expect(reply1.content_attributes['in_reply_to']).to eq(quoted.id)
      expect(inbox.messages.where(source_id: reply_payload['id']).count).to eq(1)
    end
  end

  describe 'preserving backdating and import flags when history races with webhook' do
    it 'preserves historical created_at and imported status when already written by history importer' do
      historical_ts = 2.days.ago.change(usec: 0)
      payload = build_payload(stanza: 'BACKDATED1', timestamp: historical_ts.to_i)

      contact = create(:contact, account: channel.account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us')
      conversation = create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      hist_msg = Waha::HistoryMessageWriter.new(
        channel: channel, payload: payload, conversation: conversation, kind: 'initial'
      ).perform

      expect(hist_msg.imported).to be(true)
      expect(hist_msg.created_at.to_i).to eq(historical_ts.to_i)

      # Live webhook arrives afterwards for the same message
      live_result = perform(payload)

      expect(live_result.id).to eq(hist_msg.id)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
      hist_msg.reload
      expect(hist_msg.imported).to be(true)
      expect(hist_msg.created_at.to_i).to eq(historical_ts.to_i)
    end
  end
end
