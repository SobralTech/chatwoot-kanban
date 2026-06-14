require 'rails_helper'

RSpec.describe ConversationAssistant::SendToCustomerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:assistant_message) do
    create(
      :conversation_assistant_message,
      account: account,
      conversation: conversation,
      user: user,
      suggested_reply: 'Resposta para o cliente',
      internal_note: 'Observacao interna',
      sources: [{ 'title' => 'Fonte', 'url' => 'https://example.com' }]
    )
  end

  it 'sends only the suggested reply to the customer' do
    message = described_class.new(assistant_message: assistant_message, user: user).perform

    expect(message).to be_outgoing
    expect(message.private).to be(false)
    expect(message.content).to eq('Resposta para o cliente')
    expect(message.content).not_to include('Observacao interna')
    expect(message.content).not_to include('example.com')
  end

  it 'updates sent message tracking fields' do
    message = described_class.new(assistant_message: assistant_message, user: user).perform

    expect(assistant_message.reload.sent_message_id).to eq(message.id)
    expect(assistant_message.sent_to_customer_at).to be_present
    expect(assistant_message).to be_sent_to_customer
  end
end
