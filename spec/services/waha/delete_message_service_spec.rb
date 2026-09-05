require 'rails_helper'

RSpec.describe Waha::DeleteMessageService do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: :outgoing, source_id: 'true_5511888888888@c.us_FIRST')
  end

  it 'revokes every confirmed multipart source in deterministic order' do
    attempt = WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id, status: :sent)
    attempt.delivery_parts.create!(position: 0, part_type: :text, status: :sent,
                                   source_id: 'true_5511888888888@c.us_FIRST', external_id: 'FIRST')
    attempt.delivery_parts.create!(position: 1, part_type: :attachment, status: :sent,
                                   attachment: message.attachments.create!(account: channel.account, file_type: :image),
                                   source_id: 'true_5511888888888@c.us_SECOND', external_id: 'SECOND')
    requests = []
    %w[FIRST SECOND].each do |source_id|
      stub_request(:delete, "https://waha.test/api/#{channel.session_name}/chats/#{contact_inbox.source_id}/messages/true_5511888888888@c.us_#{source_id}")
        .to_return do
          requests << source_id
          { status: 200, body: '{}' }
        end
    end

    described_class.new(message: message).perform

    expect(requests).to eq(%w[FIRST SECOND])
  end
end
