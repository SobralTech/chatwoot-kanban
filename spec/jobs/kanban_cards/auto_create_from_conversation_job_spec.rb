require 'rails_helper'

RSpec.describe KanbanCards::AutoCreateFromConversationJob do
  subject(:job) { described_class.perform_later(conversation.id) }

  let(:conversation) { create(:conversation) }

  it 'queues the job on the low queue' do
    expect { job }.to have_enqueued_job(described_class)
      .with(conversation.id)
      .on_queue('low')
  end

  it 'calls the auto-create service for an existing conversation' do
    service = instance_double(KanbanCards::AutoCreateFromConversationService, perform!: true)
    allow(KanbanCards::AutoCreateFromConversationService).to receive(:new).and_return(service)

    described_class.perform_now(conversation.id)

    expect(KanbanCards::AutoCreateFromConversationService).to have_received(:new).with(conversation)
    expect(service).to have_received(:perform!)
  end

  it 'no-ops when the conversation no longer exists' do
    missing_conversation_id = conversation.id
    conversation.destroy!

    expect(KanbanCards::AutoCreateFromConversationService).not_to receive(:new)

    described_class.perform_now(missing_conversation_id)
  end

  it 'propagates service exceptions for retry' do
    service = instance_double(KanbanCards::AutoCreateFromConversationService)
    allow(KanbanCards::AutoCreateFromConversationService).to receive(:new).and_return(service)
    allow(service).to receive(:perform!).and_raise(StandardError, 'service failed')

    expect { described_class.perform_now(conversation.id) }.to raise_error(StandardError, 'service failed')
  end
end
