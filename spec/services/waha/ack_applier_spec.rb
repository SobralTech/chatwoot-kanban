require 'rails_helper'

describe Waha::AckApplier do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  # GOWS builds a direct-chat ack id as `fromMe_chat_stanza`, and a group one as
  # `fromMe_chat_stanza_messageSender` (see receiptToMessageAck upstream).
  def direct_ack(stanza:, ack:)
    { 'id' => "true_5511888888888@c.us_#{stanza}", 'from' => '5511888888888@c.us', 'to' => nil,
      'participant' => nil, 'fromMe' => true, 'ack' => ack }
  end

  def apply(payload, group: false)
    described_class.new(channel: channel, payload: payload, group: group).perform
  end

  def outgoing_message(stanza: 'DIRECT1', status: :sent, conversation_record: conversation, chat_jid: '5511888888888@c.us')
    create_waha_message(conversation: conversation_record, inbox: inbox, account: channel.account,
                        message_type: :outgoing, status: status, source_id: "true_#{chat_jid}_#{stanza}")
  end

  describe 'direct conversation' do
    it 'advances the bubble through sent, delivered and read' do
      message = outgoing_message

      apply(direct_ack(stanza: 'DIRECT1', ack: 2))
      expect(message.reload.status).to eq('delivered')

      apply(direct_ack(stanza: 'DIRECT1', ack: 3))
      expect(message.reload.status).to eq('read')
    end

    it 'treats a repeated ack as a no-op' do
      message = outgoing_message

      2.times { apply(direct_ack(stanza: 'DIRECT1', ack: 3)) }

      expect(message.reload.status).to eq('read')
    end

    it 'never moves a read message back to delivered when acks arrive out of order' do
      message = outgoing_message

      apply(direct_ack(stanza: 'DIRECT1', ack: 3))
      apply(direct_ack(stanza: 'DIRECT1', ack: 2))

      expect(message.reload.status).to eq('read')
    end

    it 'ignores an ack for an incoming message' do
      message = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                    message_type: :incoming, source_id: 'false_5511888888888@c.us_INCOMING')

      apply(direct_ack(stanza: 'INCOMING', ack: 3).merge('fromMe' => false))

      expect(message.reload.status).to eq('sent')
    end

    it 'does not resolve an ack whose stanza belongs to another chat' do
      other_contact_inbox = create(:contact_inbox, inbox: inbox, source_id: '5511777777777@c.us',
                                                   contact: create(:contact, account: channel.account, phone_number: '+5511777777777'))
      other_conversation = create(:conversation, account: channel.account, inbox: inbox,
                                                 contact: other_contact_inbox.contact, contact_inbox: other_contact_inbox)
      message = outgoing_message(stanza: 'SHARED1', conversation_record: other_conversation, chat_jid: '5511777777777@c.us')

      expect(apply(direct_ack(stanza: 'SHARED1', ack: 3))).to be(false)
      expect(message.reload.status).to eq('sent')
    end
  end

  describe 'an ack that lands before its message' do
    it 'reports the ack as unapplied so the caller can replay it, then applies it once the message exists' do
      expect(apply(direct_ack(stanza: 'EARLY1', ack: 3))).to be(false)

      message = outgoing_message(stanza: 'EARLY1')
      expect(apply(direct_ack(stanza: 'EARLY1', ack: 3))).to be(true)
      expect(message.reload.status).to eq('read')
    end
  end

  describe 'multipart aggregation' do
    let(:message) do
      create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                          message_type: :outgoing, status: :sent, source_id: 'true_5511888888888@c.us_PART0')
    end
    let(:attempt) do
      WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                                  status: :sent, external_id: 'PART0')
    end

    before do
      %w[PART0 PART1].each_with_index do |external_id, position|
        attachment = position.zero? ? nil : message.attachments.create!(account: channel.account, file_type: :image)
        attempt.delivery_parts.create!(position: position, part_type: position.zero? ? :text : :attachment,
                                       status: :sent, external_id: external_id, attachment: attachment,
                                       source_id: "true_5511888888888@c.us_#{external_id}")
        unless position.zero?
          WahaMessageMapping.create_canonical!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                                               external_id: external_id, direction: :outgoing, part: position)
        end
      end
    end

    it 'keeps the aggregate at sent while one part has no receipt yet' do
      apply(direct_ack(stanza: 'PART0', ack: 3))

      expect(message.reload.status).to eq('sent')
      expect(attempt.delivery_parts.find_by(position: 0).ack_status).to eq('read')
      expect(attempt.delivery_parts.find_by(position: 1).ack_status).to be_nil
    end

    it 'aggregates to the weakest state across the parts' do
      apply(direct_ack(stanza: 'PART0', ack: 3))
      apply(direct_ack(stanza: 'PART1', ack: 2))

      expect(message.reload.status).to eq('delivered')
    end

    it 'reaches read only once every part was read' do
      apply(direct_ack(stanza: 'PART0', ack: 3))
      apply(direct_ack(stanza: 'PART1', ack: 2))
      apply(direct_ack(stanza: 'PART1', ack: 3))

      expect(message.reload.status).to eq('read')
    end

    it 'keeps a failed part visible even when the other part was read' do
      apply(direct_ack(stanza: 'PART0', ack: 3))
      apply(direct_ack(stanza: 'PART1', ack: -1))

      expect(message.reload.status).to eq('failed')
      expect(attempt.delivery_parts.find_by(position: 0).ack_status).to eq('read')
    end
  end

  describe 'failure transitions' do
    it 'fails a message on an error ack correlated to its accepted attempt' do
      message = outgoing_message
      create_waha_attempt(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                          status: :sent, external_id: 'DIRECT1')

      apply(direct_ack(stanza: 'DIRECT1', ack: -1))

      expect(message.reload).to have_attributes(status: 'failed', external_error: be_present)
    end

    it 'leaves a delivered message alone when a stale error ack arrives' do
      message = outgoing_message(status: :delivered)
      create_waha_attempt(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                          status: :sent, external_id: 'DIRECT1')

      apply(direct_ack(stanza: 'DIRECT1', ack: -1))

      expect(message.reload.status).to eq('delivered')
    end

    it 'refuses to fail a message when the ack cannot be tied to its attempt' do
      message = outgoing_message
      create_waha_attempt(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                          status: :sent, external_id: 'OTHERATTEMPT')

      apply(direct_ack(stanza: 'DIRECT1', ack: -1))

      expect(message.reload.status).to eq('sent')
    end

    it 'lifts a failed message when the ack belongs to the attempt WAHA accepted' do
      message = outgoing_message(status: :failed)
      message.update!(external_error: 'timeout')
      create_waha_attempt(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                          status: :sent, external_id: 'DIRECT1')

      apply(direct_ack(stanza: 'DIRECT1', ack: 2))

      expect(message.reload).to have_attributes(status: 'delivered', external_error: nil)
    end

    it 'keeps a failed message failed when the ack belongs to an attempt that was never accepted' do
      message = outgoing_message(status: :failed)
      create_waha_attempt(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                          status: :failed, client_message_id: 'DIRECT1')

      apply(direct_ack(stanza: 'DIRECT1', ack: 2))

      expect(message.reload.status).to eq('failed')
    end
  end

  describe 'group acks' do
    let(:group_inbox) { create(:contact_inbox, inbox: inbox, source_id: '1203630000@g.us', contact: create(:contact, account: channel.account)) }
    let(:group_conversation) do
      create(:conversation, account: channel.account, inbox: inbox, contact: group_inbox.contact, contact_inbox: group_inbox)
    end
    let(:group_message) { outgoing_message(stanza: 'GROUP1', conversation_record: group_conversation, chat_jid: '1203630000@g.us') }

    # GOWS reverses the receipt's IsFromMe and puts the reader in `participant`.
    def group_ack(ack:, participant: '5511777777777@c.us', stanza: 'GROUP1')
      { 'id' => "true_1203630000@g.us_#{stanza}_5511999999999@c.us", 'from' => '1203630000@g.us',
        'to' => participant, 'participant' => participant, 'fromMe' => true, 'ack' => ack }
    end

    it 'records each participant separately and advances the bubble' do
      group_message

      apply(group_ack(ack: 2, participant: '5511777777777@c.us'), group: true)
      apply(group_ack(ack: 3, participant: '5511666666666@c.us'), group: true)

      expect(group_message.reload.status).to eq('read')
      expect(group_message.content_attributes['waha_group_acks']).to eq(
        '5511777777777@c.us' => 'delivered', '5511666666666@c.us' => 'read'
      )
    end

    it 'never downgrades a participant that already read the message' do
      group_message

      apply(group_ack(ack: 3), group: true)
      apply(group_ack(ack: 2), group: true)

      expect(group_message.reload.status).to eq('read')
      expect(group_message.content_attributes['waha_group_acks']).to eq('5511777777777@c.us' => 'read')
    end

    it 'produces an observable signal and no state change when the payload carries no participant' do
      group_message
      allow(Rails.logger).to receive(:warn)

      apply(group_ack(ack: 3, participant: nil).merge('to' => nil), group: true)

      expect(Rails.logger).to have_received(:warn).with(/Group ack without participant granularity/)
      expect(group_message.reload.status).to eq('sent')
      expect(group_message.content_attributes['waha_group_acks']).to be_nil
    end
  end
end
