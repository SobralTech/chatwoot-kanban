require 'rails_helper'

RSpec.describe KanbanCards::EvaluateContactRecurrenceJob do
  let(:conversation) { create(:conversation) }
  let(:kanban_board) { create(:kanban_board, account: conversation.account) }

  it 'queues the job on the low queue' do
    expect { described_class.perform_later(conversation.id, kanban_board.id, conversation.inbox_id) }
      .to have_enqueued_job(described_class)
      .with(conversation.id, kanban_board.id, conversation.inbox_id)
      .on_queue('low')
  end

  it 'calls the recurrence service for existing records' do
    service = instance_double(KanbanCards::EvaluateContactRecurrenceService, perform!: true)
    allow(KanbanCards::EvaluateContactRecurrenceService).to receive(:new).and_return(service)

    described_class.perform_now(conversation.id, kanban_board.id, conversation.inbox_id)

    expect(KanbanCards::EvaluateContactRecurrenceService).to have_received(:new).with(
      conversation: conversation,
      kanban_board: kanban_board,
      inbox: conversation.inbox
    )
    expect(service).to have_received(:perform!)
  end

  it 'no-ops when the conversation or board no longer exists' do
    conversation_id = conversation.id
    kanban_board_id = kanban_board.id
    conversation.destroy!
    kanban_board.destroy!

    expect(KanbanCards::EvaluateContactRecurrenceService).not_to receive(:new)

    described_class.perform_now(conversation_id, kanban_board_id, nil)
  end
end
