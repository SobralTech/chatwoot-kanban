require 'rails_helper'
require 'database_cleaner/active_record'

describe Webhooks::WahaEventsJob do
  let(:channel) { create(:channel_waha, groups_enabled: true) }
  let(:inbox) { channel.inbox }
  let(:chat) { '120363000000000000@g.us' }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: chat) }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox, contact_inbox: contact_inbox, contact: contact) }
  let(:base) do
    create_waha_message(account: channel.account, inbox: inbox, conversation: conversation,
                        source_id: "false_#{chat}_BASE", content: 'Original')
  end

  def event(name, payload)
    { 'session' => channel.session_name, 'event' => "message.#{name}", 'payload' => payload }
  end

  def reaction(emoji, participant = '5511888888888@c.us')
    event('reaction', { 'id' => "false_#{chat}_REACTION_#{participant}", 'from' => chat, 'fromMe' => false,
                        'participant' => participant, 'timestamp' => 1_778_000_000,
                        'reaction' => { 'text' => emoji, 'messageId' => "false_#{chat}_BASE" } })
  end

  # GOWS emits a bare protocolMessage.key.ID, before:null and an after envelope.
  def revoke
    event('revoked', { 'revokedMessageId' => 'BASE', 'before' => nil,
                       'after' => { 'id' => "false_#{chat}_REVOKE", 'from' => chat, 'fromMe' => false } })
  end

  def edit
    event('edited', { 'id' => "false_#{chat}_EDIT", 'editedMessageId' => 'BASE', 'from' => chat,
                      'fromMe' => false, 'body' => 'Updated', 'hasMedia' => false, 'type' => 'chat',
                      '_data' => { 'Info' => { 'Chat' => chat } } })
  end

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  it 'replaces and removes only the matching participant and deduplicates activities' do
    base
    described_class.perform_now(channel.id, reaction('👍'))
    described_class.perform_now(channel.id, reaction('❤️', '5511777777777@c.us'))
    described_class.perform_now(channel.id, reaction('👍'))
    expect(conversation.messages.activity.count).to eq(2)

    described_class.perform_now(channel.id, reaction('🔥'))
    expect(base.reload.content_attributes['reactions'].transform_values { |value| value['emoji'] })
      .to eq('5511888888888@c.us' => '🔥', '5511777777777@c.us' => '❤️')
    described_class.perform_now(channel.id, reaction(''))
    described_class.perform_now(channel.id, reaction(''))
    expect(base.reload.content_attributes['reactions'].keys).to eq(['5511777777777@c.us'])
    expect(conversation.messages.activity.count).to eq(3)
  end

  it 'replays a reaction delivered before its base and keeps chips on the current edit head' do
    params = reaction('👍')
    expect { described_class.perform_now(channel.id, params) }.to have_enqueued_job(described_class).with(channel.id, params, 1)
    base
    described_class.perform_now(channel.id, params, 1)
    described_class.perform_now(channel.id, edit)
    head = waha_messages("false_#{chat}_EDIT", inbox.messages).first!
    expect(base.reload.content_attributes['reactions']).to be_nil
    expect(head.content_attributes.dig('reactions', '5511888888888@c.us', 'emoji')).to eq('👍')

    described_class.perform_now(channel.id, reaction('❤️', '5511777777777@c.us'))
    expect(head.reload.content_attributes['reactions'].size).to eq(2)
    expect(base.reload.content_attributes['reactions']).to be_nil
  end

  it 'replays an early revoke and preserves real deletion on redelivery and late mutations' do
    params = revoke
    expect { described_class.perform_now(channel.id, params) }
      .to have_enqueued_job(described_class).with(channel.id, params, 1)
      .at(a_value_within(1.second).of(described_class::ACK_RETRY_DELAY.from_now))
    base
    described_class.perform_now(channel.id, reaction('👍'))
    described_class.perform_now(channel.id, edit)
    attachment = base.attachments.create!(account: channel.account, file_type: :image)

    described_class.perform_now(channel.id, params, 1)
    described_class.perform_now(channel.id, params)
    described_class.perform_now(channel.id, reaction('❤️'))
    described_class.perform_now(channel.id, edit)

    family = Waha::Anchoring.family(inbox, base)
    expect(family.count).to eq(2)
    family.each do |message|
      expect(message.content_attributes['deleted']).to be(true)
      expect(message.content_attributes['reactions']).to be_nil
      expect(message.content).to eq(I18n.t('conversations.messages.deleted'))
    end
    expect(Attachment.exists?(attachment.id)).to be(false)
  end

  it 'rolls back a transient attachment deletion failure and succeeds on the queued retry' do
    base
    described_class.perform_now(channel.id, edit)
    head = waha_messages("false_#{chat}_EDIT", inbox.messages).first!
    attachment = head.attachments.create!(account: channel.account, file_type: :image)
    attempts = 0
    allow_any_instance_of(Attachment).to receive(:destroy!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      attempts += 1
      raise ActiveRecord::Deadlocked, 'temporary failure' if attempts == 1

      original.call(*args)
    end
    params = revoke
    expect { described_class.perform_now(channel.id, params) }.to have_enqueued_job(described_class).with(channel.id, params, 1)
    expect([base, head].map { |message| message.reload.content_attributes['deleted'] }).to eq([nil, nil])
    expect(Attachment.exists?(attachment.id)).to be(true)

    perform_enqueued_jobs(only: described_class)

    expect(attempts).to eq(2)
    expect([base, head].map { |message| message.reload.content_attributes['deleted'] }).to eq([true, true])
    expect(Attachment.exists?(attachment.id)).to be(false)
  end

  it 'limits missing-anchor retries and reports exhaustion' do
    params = revoke
    signals = capture_waha_signals do
      expect { perform_enqueued_jobs(only: described_class) { described_class.perform_later(channel.id, params) } }
        .to have_performed_job(described_class).exactly(4).times
    end

    expect(waha_signal(signals, :event_retry_scheduled).size).to eq(3)
    expect(waha_signal(signals, :event_retries_exhausted).first).to include(reason: :missing_anchor, try: 3)
  end

  it 'does not revoke the same stanza in a different chat' do
    other = create_waha_message(account: channel.account, inbox: inbox, conversation: conversation,
                                source_id: 'false_5511666666666@c.us_BASE', content: 'Unrelated')
    base
    described_class.perform_now(channel.id, revoke)
    expect(base.reload.content_attributes['deleted']).to be(true)
    expect(other.reload.content).to eq('Unrelated')
  end

  it 'exhausts transient failures after three retries without marking a failed deletion complete' do
    base.attachments.create!(account: channel.account, file_type: :image)
    allow_any_instance_of(Attachment).to receive(:destroy!).and_raise(ActiveRecord::Deadlocked) # rubocop:disable RSpec/AnyInstance
    params = revoke

    signals = capture_waha_signals do
      expect { perform_enqueued_jobs(only: described_class) { described_class.perform_later(channel.id, params) } }
        .to have_performed_job(described_class).exactly(4).times
    end

    expect(base.reload.content_attributes['deleted']).to be_nil
    expect(base.attachments.count).to eq(1)
    expect(waha_signal(signals, :event_retries_exhausted).first).to include(reason: 'ActiveRecord::Deadlocked', try: 3)
  end

  describe 'concurrent database transactions' do
    self.use_transactional_tests = false

    around do |example|
      cleaner = DatabaseCleaner[:active_record]
      cleaner.strategy = :deletion
      cleaner.cleaning { example.run }
    end

    def concurrently(*operations)
      barrier = Concurrent::CyclicBarrier.new(operations.size)
      threads = operations.map do |operation|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            raise 'Concurrent start timed out' unless barrier.wait(10)

            operation.call
          end
        end
      end
      threads.each(&:value)
    end

    it 'merges two stale message snapshots under a real row lock without losing either chip' do
      targets = [Message.find(base.id), Message.find(base.id)]
      params = [reaction('👍'), reaction('❤️', '5511777777777@c.us')]
      appliers = targets.zip(params).map do |target, event_params|
        Waha::ReactionApplier.new(channel: channel, target_message: target, payload: event_params['payload'])
      end

      concurrently(*appliers.map { |applier| -> { applier.perform } })

      expect(base.reload.content_attributes['reactions'].transform_values { |value| value['emoji'] })
        .to eq('5511888888888@c.us' => '👍', '5511777777777@c.us' => '❤️')
      expect(conversation.messages.activity.count).to eq(2)
    end

    it 'deduplicates concurrent reactions from the same participant' do
      base
      params = reaction('👍')
      channel_id = channel.id
      operation = -> { described_class.perform_now(channel_id, params) }

      concurrently(operation, operation)

      expect(base.reload.content_attributes['reactions'].size).to eq(1)
      expect(conversation.messages.activity.count).to eq(1)
    end

    it 'keeps reactions on the new head when an edit races a reaction' do
      base
      events = [reaction('👍'), edit]
      channel_id = channel.id

      concurrently(*events.map { |params| -> { described_class.perform_now(channel_id, params) } })

      head = waha_messages("false_#{chat}_EDIT", inbox.messages).first!
      expect(head.content_attributes.dig('reactions', '5511888888888@c.us', 'emoji')).to eq('👍')
      expect(base.reload.content_attributes['reactions']).to be_nil
      expect(base.additional_attributes['superseded']).to be(true)
      expect(head.additional_attributes['superseded']).to be_blank
    end

    it 'converges to deletion when revocation races an edit and a reaction' do
      base
      events = [revoke, edit, reaction('👍')]
      channel_id = channel.id

      concurrently(*events.map { |params| -> { described_class.perform_now(channel_id, params) } })

      Waha::Anchoring.family(inbox, base).each do |message|
        expect(message.content_attributes['deleted']).to be(true)
        expect(message.content_attributes['reactions']).to be_nil
      end
    end
  end
end
