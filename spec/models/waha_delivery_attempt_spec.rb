require 'rails_helper'

RSpec.describe WahaDeliveryAttempt do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, message_type: :outgoing)
  end

  def build_attempt(**attrs)
    described_class.new({ channel: channel, message: message, chat_jid: '5511888888888@c.us' }.merge(attrs)).tap do |attempt|
      attempt.delivery_parts.build(position: 0, part_type: :text, status: attempt.sent? ? :sent : :pending,
                                   client_message_id: attrs[:client_message_id], external_id: attrs[:external_id])
    end
  end

  it 'requires a chat_jid' do
    attempt = build_attempt(chat_jid: nil)

    expect(attempt).to be_invalid
    expect(attempt.errors[:chat_jid]).to be_present
  end

  it 'allows only one attempt row per message' do
    build_attempt.save!
    duplicate = build_attempt

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe '#claim!' do
    it 'transitions pending -> sending and bumps attempt_count' do
      attempt = build_attempt.tap(&:save!)

      expect(attempt.claim!).to be(true)
      expect(attempt.reload).to have_attributes(status: 'sending', attempt_count: 1)
    end

    it 'reclaims a failed attempt for a manual resend' do
      attempt = build_attempt(status: :failed, attempt_count: 3).tap(&:save!)

      expect(attempt.claim!).to be(true)
      expect(attempt.reload).to have_attributes(status: 'sending', attempt_count: 4)
    end

    it 'refuses to claim an attempt that is already sending' do
      attempt = build_attempt(status: :sending).tap(&:save!)

      expect(attempt.claim!).to be(false)
      expect(attempt.reload.attempt_count).to eq(0)
    end

    it 'refuses to claim an attempt that is already sent' do
      attempt = build_attempt(status: :sent, external_id: 'AAA111').tap(&:save!)

      expect(attempt.claim!).to be(false)
    end
  end

  describe '#confirm_sent!' do
    it 'sets the message source_id, records a canonical mapping, and marks the attempt sent' do
      attempt = build_attempt(status: :sending, client_message_id: 'GENID001').tap(&:save!)

      attempt.confirm_sent!('true_5511888888888@c.us_GENID001')

      expect(message.reload.source_id).to be_nil
      expect(message.presented_source_id).to eq('true_5511888888888@c.us_GENID001')
      expect(attempt.reload.status).to eq('sent')
      expect(attempt.delivery_parts.first.external_id).to eq('GENID001')
      mapping = WahaMessageMapping.find_by!(message: message)
      expect(mapping).to have_attributes(chat_jid: '5511888888888@c.us', external_id: 'GENID001', direction: 'outgoing')
    end

    it 'is idempotent once already sent' do
      attempt = build_attempt(status: :sent, external_id: 'GENID001').tap(&:save!)
      message.update!(source_id: 'true_5511888888888@c.us_GENID001')
      WahaMessageMapping.create_canonical!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                                           external_id: 'GENID001', direction: :outgoing)

      expect { attempt.confirm_sent!('true_5511888888888@c.us_GENID001') }.not_to raise_error
      expect(WahaMessageMapping.where(message: message).count).to eq(1)
    end
  end

  describe '.find_by_correlated_id' do
    it 'finds an attempt by its pre-generated client_message_id' do
      attempt = build_attempt(client_message_id: 'GENID001').tap(&:save!)

      found = described_class.find_by_correlated_id(channel: channel, wa_message_id: 'true_5511888888888@c.us_GENID001')
      expect(found).to eq(attempt)
    end

    it 'falls back to a confirmed external_id when no client_message_id was used' do
      attempt = build_attempt(status: :sent, external_id: 'CONF001').tap(&:save!)

      found = described_class.find_by_correlated_id(channel: channel, wa_message_id: 'true_5511888888888@c.us_CONF001')
      expect(found).to eq(attempt)
    end

    it 'returns nil for an uncorrelated id' do
      build_attempt(client_message_id: 'GENID001').save!

      found = described_class.find_by_correlated_id(channel: channel, wa_message_id: 'true_5511888888888@c.us_OTHER99')
      expect(found).to be_nil
    end
  end
end
