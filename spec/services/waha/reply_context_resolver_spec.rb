require 'rails_helper'

RSpec.describe Waha::ReplyContextResolver do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  it 'resolves a reply to any multipart part back to the aggregate message and its first-part anchor' do
    message = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                               message_type: :outgoing, source_id: 'true_5511888888888@c.us_FIRST')
    attempt = WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id, status: :sent)
    attempt.delivery_parts.create!(position: 0, part_type: :text, status: :sent,
                                   source_id: 'true_5511888888888@c.us_FIRST', external_id: 'FIRST')
    attempt.delivery_parts.create!(position: 1, part_type: :text, status: :sent,
                                   source_id: 'true_5511888888888@c.us_SECOND', external_id: 'SECOND')
    WahaMessageMapping.create_canonical!(channel: channel, message: message, chat_jid: contact_inbox.source_id,
                                         external_id: 'SECOND', direction: :outgoing, part: 1)

    result = described_class.new(
      channel: channel, conversation: conversation, payload: { 'replyTo' => { 'id' => 'SECOND' } }
    ).perform

    expect(result).to eq(in_reply_to: message.id, in_reply_to_external_id: 'true_5511888888888@c.us_FIRST')
  end
end
