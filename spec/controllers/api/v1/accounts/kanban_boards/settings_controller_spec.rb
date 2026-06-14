require 'rails_helper'

RSpec.describe 'Kanban board settings API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:kanban_board, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{board.id}/settings/import_existing_conversations' do
    it 'enqueues the import job and returns accepted metadata' do
      create(:kanban_stage, account: account, kanban_board: board)
      create(:conversation, account: account)

      expect do
        post import_url(board),
             headers: administrator.create_new_auth_token,
             params: { ignore_groups: true },
             as: :json
      end.to have_enqueued_job(KanbanCards::ImportExistingConversationsJob).with(account.id, board.id, ignore_groups: true)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include(
        'status' => 'accepted',
        'enqueued' => true,
        'estimated_count' => 1
      )
    end

    it 'does not import conversations synchronously' do
      create(:kanban_stage, account: account, kanban_board: board)
      create(:conversation, account: account)

      expect do
        post import_url(board),
             headers: administrator.create_new_auth_token,
             params: { ignore_groups: false },
             as: :json
      end.not_to change(KanbanCard, :count)
    end

    it 'does not allow agents to enqueue imports' do
      post import_url(board),
           headers: agent.create_new_auth_token,
           params: { ignore_groups: false },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(KanbanCards::ImportExistingConversationsJob).not_to have_been_enqueued
    end

    it 'does not allow importing a board from another account' do
      other_board = create(:kanban_board)

      post import_url(other_board),
           headers: administrator.create_new_auth_token,
           params: { ignore_groups: false },
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(KanbanCards::ImportExistingConversationsJob).not_to have_been_enqueued
    end
  end

  def import_url(target_board)
    "/api/v1/accounts/#{account.id}/kanban_boards/#{target_board.id}/settings/import_existing_conversations"
  end
end
