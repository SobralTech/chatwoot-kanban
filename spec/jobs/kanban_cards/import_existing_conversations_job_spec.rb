require 'rails_helper'

RSpec.describe KanbanCards::ImportExistingConversationsJob do
  subject(:job) { described_class.perform_later(account.id, board.id, ignore_groups: true) }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }

  it 'queues the job on the low queue' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account.id, board.id, ignore_groups: true)
      .on_queue('low')
  end

  it 'calls the import service for an existing board' do
    service = instance_double(KanbanCards::ImportExistingConversationsService, perform!: true)
    allow(KanbanCards::ImportExistingConversationsService).to receive(:new).and_return(service)

    described_class.perform_now(account.id, board.id, ignore_groups: true)

    expect(KanbanCards::ImportExistingConversationsService).to have_received(:new).with(
      account: account,
      kanban_board: board,
      ignore_groups: true
    )
    expect(service).to have_received(:perform!)
  end

  it 'no-ops when the board no longer exists' do
    missing_board_id = board.id
    board.destroy!

    expect(KanbanCards::ImportExistingConversationsService).not_to receive(:new)

    described_class.perform_now(account.id, missing_board_id, ignore_groups: true)
  end
end
