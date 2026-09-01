require 'rails_helper'

describe Waha::IncomingMessageService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def build_payload(stanza:)
    {
      'id' => "false_5511888888888@c.us_#{stanza}",
      'body' => "message #{stanza}",
      'from' => '5511888888888@c.us',
      'to' => '5511999999999@c.us',
      'fromMe' => false,
      'type' => 'chat',
      'hasMedia' => false,
      '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us', 'PushName' => 'John Doe' } }
    }
  end

  def perform(payload)
    described_class.new(channel: channel, payload: payload).perform
  end

  # The dedupe check ran before the media download, which can block for a minute.
  # Sidekiq delivers at least once and WAHA retries webhooks it considers failed, so
  # the same event can be in flight twice — and both runs would pass a check taken a
  # minute before the insert. The twin is committed here from inside the download to
  # place it exactly in that window.
  describe 'a duplicate delivery of the same event' do
    it 'does not mirror the message twice when the twin lands during the media download' do
      payload = build_payload(stanza: 'AAA111')
      twin_landed = false

      allow_any_instance_of(Waha::MediaAttacher).to receive(:download) do # rubocop:disable RSpec/AnyInstance
        unless twin_landed
          twin_landed = true
          perform(build_payload(stanza: 'AAA111'))
        end
        nil
      end

      perform(payload)

      expect(twin_landed).to be(true)
      expect(inbox.messages.where(source_id: payload['id']).count).to eq(1)
    end
  end

  # A contact sending several messages in a row is the normal case on WhatsApp. Each
  # arrives as its own webhook and is processed by its own worker, so the conversation
  # must be read only after the contact_inbox row lock is held — otherwise every worker
  # finds none and creates one, splitting the contact across duplicates.
  #
  # The competing conversation is committed from inside `lock!` to stand for the worker
  # that won the lock first and committed while this one was blocked on it.
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
end
