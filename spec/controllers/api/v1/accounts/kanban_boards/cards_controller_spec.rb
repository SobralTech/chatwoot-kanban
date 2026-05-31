require 'rails_helper'

RSpec.describe 'Kanban Cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: conversation.inbox)
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards' do
    it 'creates a card for a conversation the agent can access' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id, position: 2 } },
             as: :json
      end.to change(ConversationKanbanState, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.display_id)
      expect(response.parsed_body['position']).to eq(2)
      expect(ConversationKanbanState.last.moved_by).to eq(agent)
      expect(ConversationKanbanState.last.moved_at).to be_present
    end

    it 'mirrors the legacy state into an active kanban card' do
      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
           headers: agent.create_new_auth_token,
           params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id, position: 2 } },
           as: :json

      expect(response).to have_http_status(:success)
      expect(mirrored_card_for(conversation)).to have_attributes(
        kanban_stage_id: stage.id,
        position: 2,
        active: true,
        origin: 'conversation'
      )
    end

    it 'updates the mirrored kanban card when create is repeated' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
           headers: agent.create_new_auth_token,
           params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id, position: 1 } },
           as: :json

      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: conversation.display_id, kanban_stage_id: next_stage.id, position: 3 } },
             as: :json
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:success)
      expect(mirrored_card_for(conversation).reload).to have_attributes(kanban_stage_id: next_stage.id, position: 3)
    end

    it 'rolls back the legacy create when mirroring fails' do
      allow_any_instance_of(KanbanCards::SyncConversationStateService).to receive(:sync!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id } },
             as: :json
      end.to not_change(ConversationKanbanState, :count)
        .and not_change(KanbanCard, :count)

      expect(response).to have_http_status(:internal_server_error)
    end

    it 'keeps the API response contract unchanged' do
      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
           headers: agent.create_new_auth_token,
           params: { card: { conversation_id: conversation.display_id, kanban_stage_id: stage.id, position: 2 } },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to contain_exactly(
        'id', 'account_id', 'kanban_board_id', 'kanban_stage_id', 'conversation_id', 'position', 'moved_by_id', 'moved_at',
        'created_at', 'updated_at', 'conversation'
      )
    end

    it 'does not create a card for a conversation the agent cannot access' do
      hidden_conversation = create(:conversation, account: account)

      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
             headers: agent.create_new_auth_token,
             params: { card: { conversation_id: hidden_conversation.display_id, kanban_stage_id: stage.id } },
             as: :json
      end.not_to change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not create a card on a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards",
           headers: agent.create_new_auth_token,
           params: { card: { conversation_id: conversation.display_id, kanban_stage_id: other_stage.id } },
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}' do
    it 'moves an existing card' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.kanban_stage).to eq(next_stage)
      expect(card.position).to eq(1)
      expect(card.moved_by).to eq(agent)
      expect(card.moved_at).to be_present
    end

    it 'mirrors updated stage and position' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id, position: 4 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(mirrored_card_for(conversation)).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
    end

    it 'normalizes source and destination stages when moving a card' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      source_conversation = create(:conversation, account: account)
      destination_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: source_conversation.inbox)
      create(:inbox_member, user: agent, inbox: destination_conversation.inbox)
      moving_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      source_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: source_conversation,
        position: 1
      )
      destination_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: next_stage,
        conversation: destination_conversation,
        position: 7
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(source_card.reload.position).to eq(1)
      expect(destination_card.reload.position).to eq(1)
      expect(moving_card.reload.position).to eq(2)
      expect(moving_card.kanban_stage).to eq(next_stage)
      expect(mirrored_stage_positions_for(conversation, source_conversation, destination_conversation)).to contain_exactly(
        [conversation.id, next_stage.id, 2],
        [source_conversation.id, stage.id, 1],
        [destination_conversation.id, next_stage.id, 1]
      )
    end

    it 'rolls back the legacy update when mirroring fails' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      allow_any_instance_of(KanbanCards::SyncConversationStateService).to receive(:sync!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
              headers: agent.create_new_auth_token,
              params: { card: { kanban_stage_id: next_stage.id } },
              as: :json
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:internal_server_error)
      expect(card.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end

    it 'does not fall back to stable card ID lookup' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_manual_card(id: 90_001, position: 1)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}/reorder' do
    it 'moves a card up within the same stage' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{next_conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'up' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(second_card.reload.position).to eq(1)
      expect(first_card.reload.position).to eq(2)
      expect(mirrored_card_for(next_conversation)).to have_attributes(kanban_stage_id: stage.id, position: 1)
      expect(mirrored_card_for(conversation)).to have_attributes(kanban_stage_id: stage.id, position: 2)
    end

    it 'moves a card down within the same stage' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(1)
    end

    it 'normalizes duplicated card positions before moving' do
      second_conversation = create(:conversation, account: account)
      third_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: second_conversation.inbox)
      create(:inbox_member, user: agent, inbox: third_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: second_conversation,
        position: 1
      )
      third_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: third_conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{third_conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'up' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_card.reload.position).to eq(1)
      expect(third_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'does not reorder cards from another stage' do
      next_conversation = create(:conversation, account: account)
      third_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      create(:inbox_member, user: agent, inbox: third_conversation.inbox)
      other_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      other_stage_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: other_stage,
        conversation: next_conversation,
        position: 2
      )
      third_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: third_conversation,
        position: 3
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(first_card.reload.position).to eq(2)
      expect(third_card.reload.position).to eq(1)
      expect(other_stage_card.reload.position).to eq(2)
    end

    it 'does not reorder a card from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: other_board,
        kanban_stage: other_stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { direction: 'down' },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'reorders a card by explicit position within the same stage' do
      second_conversation = create(:conversation, account: account)
      third_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: second_conversation.inbox)
      create(:inbox_member, user: agent, inbox: third_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: second_conversation,
        position: 2
      )
      third_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: third_conversation,
        position: 3
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{third_conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(third_card.reload.position).to eq(1)
      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'moves a card to another stage by explicit stage and position' do
      destination_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      destination_conversation = create(:conversation, account: account)
      source_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: destination_conversation.inbox)
      create(:inbox_member, user: agent, inbox: source_conversation.inbox)
      moving_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      source_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: source_conversation,
        position: 2
      )
      destination_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: destination_stage,
        conversation: destination_conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: destination_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(moving_card.reload.kanban_stage).to eq(destination_stage)
      expect(moving_card.position).to eq(1)
      expect(source_card.reload.position).to eq(1)
      expect(destination_card.reload.position).to eq(2)
      expect(mirrored_stage_positions_for(conversation, source_conversation, destination_conversation)).to contain_exactly(
        [conversation.id, destination_stage.id, 1],
        [source_conversation.id, stage.id, 1],
        [destination_conversation.id, destination_stage.id, 2]
      )
    end

    it 'mirrors changed sibling positions after explicit same-stage reorder' do
      second_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: second_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: second_conversation,
        position: 2
      )
      sync_state(first_card)
      sync_state(second_card)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{second_conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(mirrored_card_for(second_conversation).reload.position).to eq(1)
      expect(mirrored_card_for(conversation).reload.position).to eq(2)
    end

    it 'rolls back the legacy reorder when mirroring fails' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      first_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      second_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )
      allow_any_instance_of(KanbanCards::SyncConversationStateService).to receive(:sync!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{next_conversation.display_id}/reorder",
              headers: agent.create_new_auth_token,
              params: { direction: 'up' },
              as: :json
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:internal_server_error)
      expect(first_card.reload.position).to eq(1)
      expect(second_card.reload.position).to eq(2)
    end

    it 'does not move a card to a stage from another board with explicit payload' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: other_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'stable card ID routes' do
    it 'updates a card by stable ID' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_manual_card(position: 1)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
    end

    it 'reorders a card by stable ID within the same stage' do
      first_card = create_manual_card(position: 1)
      second_card = create_manual_card(position: 2, subject: 'Second opportunity')
      third_card = create_manual_card(position: 3, subject: 'Third opportunity')

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{third_card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(third_card.reload.position).to eq(1)
      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'reorders a card by stable ID across stages' do
      destination_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      moving_card = create_manual_card(position: 1)
      source_card = create_manual_card(position: 2, subject: 'Source opportunity')
      destination_card = create_manual_card(kanban_stage: destination_stage, position: 1, subject: 'Destination opportunity')

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{moving_card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: destination_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(moving_card.reload).to have_attributes(kanban_stage_id: destination_stage.id, position: 1)
      expect(source_card.reload.position).to eq(1)
      expect(destination_card.reload.position).to eq(2)
    end

    it 'soft-deletes a card by stable ID' do
      card = create_manual_card

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:no_content)
      expect(card.reload).not_to be_active
    end

    it 'updates, reorders, and deletes a manual card without a conversation' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_manual_card(position: 1)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json
      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(card.reload).to have_attributes(conversation_id: nil, kanban_stage_id: next_stage.id, position: 1, active: false)
    end

    it 'mirrors conversation-origin card mutations back to legacy state' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      card = sync_state(state)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(state.reload).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
    end

    it 'rejects inactive cards' do
      card = create_manual_card(active: false)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects cards from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      card = create_manual_card(kanban_board: other_board, kanban_stage: other_stage)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects unauthorized cards' do
      hidden_inbox = create(:inbox, account: account)
      card = create_manual_card(inbox: hidden_inbox)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: stage.id } },
            as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not fall back to conversation display ID lookup' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{conversation.display_id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end

    it 'uses stable ID when it collides with a conversation display ID' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      legacy_card = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      stable_card = create_manual_card(id: conversation.display_id, position: 2, subject: 'Collision opportunity')

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{stable_card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(stable_card.reload).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
      expect(legacy_card.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/{conversation_id}' do
    it 'removes a card from the board' do
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.to change(ConversationKanbanState, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'deactivates the mirrored kanban card and keeps it stored' do
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )
      mirrored_card = sync_state(state)

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:no_content)
      expect(mirrored_card.reload).not_to be_active
    end

    it 'mirrors remaining normalized sibling positions' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      sibling_state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 3
      )
      sync_state(state)
      sync_state(sibling_state)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(sibling_state.reload.position).to eq(1)
      expect(mirrored_card_for(next_conversation).reload.position).to eq(1)
    end

    it 'rolls back the legacy delete when mirroring fails' do
      next_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: next_conversation.inbox)
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: next_conversation,
        position: 2
      )
      mirrored_card = sync_state(state)
      allow_any_instance_of(KanbanCards::SyncConversationStateService).to receive(:sync!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/#{conversation.display_id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.to not_change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:internal_server_error)
      expect(state.reload).to be_present
      expect(mirrored_card.reload).to be_active
    end
  end

  def mirrored_card_for(conversation)
    KanbanCard.conversation.find_by(kanban_board: kanban_board, conversation: conversation)
  end

  def mirrored_stage_positions_for(*conversations)
    conversations.map do |conversation|
      card = mirrored_card_for(conversation)
      [conversation.id, card.kanban_stage_id, card.position]
    end
  end

  def sync_state(state)
    KanbanCards::SyncConversationStateService.new(state).sync!
  end

  def create_manual_card(attributes = {})
    create(
      :kanban_card,
      {
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: conversation.contact,
        inbox: conversation.inbox
      }.merge(attributes)
    )
  end
end
