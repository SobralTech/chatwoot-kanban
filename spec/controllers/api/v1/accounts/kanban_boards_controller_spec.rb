require 'rails_helper'

RSpec.describe 'Kanban Boards API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:kanban_board) { create(:kanban_board, account: account, name: 'Sales', use_opportunity_card_reads: false) }

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards' do
    it 'returns unauthorized for unauthenticated users' do
      get "/api/v1/accounts/#{account.id}/kanban_boards"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns boards for agents' do
      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['name']).to eq('Sales')
      expect(response.parsed_body.first['auto_create_cards_from_conversations']).to be(false)
      expect(response.parsed_body.first['use_opportunity_card_reads']).to be(false)
    end

    it 'does not return inactive boards' do
      create(:kanban_board, account: account, active: false)

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('active')).to all be(true)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'returns board stages and cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New')
      conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: conversation.inbox)
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      )

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['use_opportunity_card_reads']).to be(false)
      expect(response.parsed_body['stages'].first['name']).to eq('New')
      expect(response.parsed_body['stages'].first['cards'].first['conversation_id']).to eq(conversation.display_id)
    end

    it 'does not return boards from another account' do
      other_board = create(:kanban_board)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{other_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns stages and cards ordered by position' do
      later_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Later', position: 2)
      earlier_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Earlier', position: 1)
      later_conversation = create(:conversation, account: account)
      earlier_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: later_conversation.inbox)
      create(:inbox_member, user: agent, inbox: earlier_conversation.inbox)
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: earlier_stage,
        conversation: later_conversation,
        position: 2
      )
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: earlier_stage,
        conversation: earlier_conversation,
        position: 1
      )

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].pluck('id')).to eq([earlier_stage.id, later_stage.id])
      expect(response.parsed_body['stages'].first['cards'].pluck('conversation_id')).to eq(
        [earlier_conversation.display_id, later_conversation.display_id]
      )
    end

    context 'when reading kanban cards' do
      it 'returns active conversation-origin kanban cards with the frontend-compatible payload' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New')
        conversation = create(:conversation, account: account)
        moved_at = 1.hour.ago.change(usec: 0)
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        card = create(
          :kanban_card,
          :conversation_origin,
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
          conversation: conversation,
          position: 99,
          moved_by: administrator,
          moved_at: moved_at
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        response_card = response.parsed_body['stages'].first['cards'].first
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['use_opportunity_card_reads']).to be(false)
        expect(response_card).to include(
          'id' => card.id,
          'conversation_id' => conversation.display_id,
          'kanban_stage_id' => stage.id,
          'position' => 1,
          'moved_by_id' => nil,
          'moved_at' => nil,
          'origin' => 'conversation',
          'subject' => nil,
          'active' => true
        )
        expect(response_card['conversation']['id']).to eq(conversation.display_id)
      end

      it 'returns active manual kanban cards without conversations with nullable conversation fields' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New')
        contact = create(:contact, account: account)
        inbox = create(:inbox, account: account)
        create(:inbox_member, user: agent, inbox: inbox)
        card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          contact: contact,
          inbox: inbox,
          subject: 'Expansion opportunity',
          position: 1
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        response_card = response.parsed_body['stages'].first['cards'].first
        expect(response).to have_http_status(:success)
        expect(response_card).to include(
          'id' => card.id,
          'origin' => 'manual',
          'subject' => 'Expansion opportunity',
          'active' => true,
          'kanban_stage_id' => stage.id,
          'position' => 1,
          'conversation_id' => nil,
          'conversation' => nil,
          'moved_by_id' => nil,
          'moved_at' => nil
        )
        expect(response_card['contact']['id']).to eq(contact.id)
        expect(response_card['inbox']['id']).to eq(inbox.id)
      end

      it 'returns active manual kanban cards with optional conversation payloads' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New')
        conversation = create(:conversation, account: account)
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          contact: conversation.contact,
          inbox: conversation.inbox,
          conversation: conversation,
          subject: 'Renewal opportunity'
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        response_card = response.parsed_body['stages'].first['cards'].first
        expect(response).to have_http_status(:success)
        expect(response_card).to include(
          'id' => card.id,
          'origin' => 'manual',
          'subject' => 'Renewal opportunity',
          'conversation_id' => conversation.display_id
        )
        expect(response_card['conversation']['id']).to eq(conversation.display_id)
      end

      it 'excludes inactive, orphan, and unauthorized cards' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        permitted_conversation = create(:conversation, account: account)
        unauthorized_conversation = create(:conversation, account: account)
        inactive_conversation = create(:conversation, account: account)
        orphan_conversation = create(:conversation, account: account)
        create(:inbox_member, user: agent, inbox: permitted_conversation.inbox)
        permitted_card = create(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          conversation: permitted_conversation
        )
        create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage)
        create(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          conversation: inactive_conversation,
          active: false
        )
        create(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          conversation: unauthorized_conversation
        )
        orphan_card = create(
          :kanban_card,
          :conversation_origin,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          conversation: orphan_conversation
        )
        orphan_card.update_column(:conversation_id, nil) # rubocop:disable Rails/SkipsModelValidations

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([permitted_card.id])
      end

      it 'filters manual kanban cards when the agent lacks inbox access' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        permitted_inbox = create(:inbox, account: account)
        unauthorized_inbox = create(:inbox, account: account)
        create(:inbox_member, user: agent, inbox: permitted_inbox)
        permitted_card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          inbox: permitted_inbox,
          contact: create(:contact, account: account)
        )
        create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          inbox: unauthorized_inbox,
          contact: create(:contact, account: account)
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([permitted_card.id])
      end

      it 'allows administrators to see valid manual kanban cards' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage)

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
      end

      it 'excludes inactive manual kanban cards' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        inbox = create(:inbox, account: account)
        create(:inbox_member, user: agent, inbox: inbox)
        active_card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          inbox: inbox,
          contact: create(:contact, account: account)
        )
        create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          inbox: inbox,
          contact: create(:contact, account: account),
          active: false
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([active_card.id])
      end

      it 'allows administrators to see permitted kanban cards' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        conversation = create(:conversation, account: account)
        card = create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: conversation)

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
      end

      it 'allows agents with team visibility to see permitted kanban cards' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        team = create(:team, account: account)
        conversation = create(:conversation, :with_team, account: account, team: team)
        create(:team_member, user: agent, team: team)
        card = create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: conversation)

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
      end

      it 'groups cards under the correct stage with deterministic ordering' do
        later_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
        earlier_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
        first_conversation = create(:conversation, account: account)
        second_conversation = create(:conversation, account: account)
        later_stage_conversation = create(:conversation, account: account)
        create(:inbox_member, user: agent, inbox: first_conversation.inbox)
        create(:inbox_member, user: agent, inbox: second_conversation.inbox)
        create(:inbox_member, user: agent, inbox: later_stage_conversation.inbox)
        second_card = create(
          :kanban_card,
          :conversation_origin,
          kanban_board: kanban_board,
          kanban_stage: earlier_stage,
          conversation: second_conversation,
          position: 2
        )
        first_card = create(
          :kanban_card,
          :conversation_origin,
          kanban_board: kanban_board,
          kanban_stage: earlier_stage,
          conversation: first_conversation,
          position: 1
        )
        later_stage_card = create(
          :kanban_card,
          :conversation_origin,
          kanban_board: kanban_board,
          kanban_stage: later_stage,
          conversation: later_stage_conversation,
          position: 1
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].pluck('id')).to eq([earlier_stage.id, later_stage.id])
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([first_card.id, second_card.id])
        expect(response.parsed_body['stages'].second['cards'].pluck('id')).to eq([later_stage_card.id])
      end

      it 'groups and orders manual and conversation-origin kanban cards together' do
        later_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
        earlier_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
        conversation = create(:conversation, account: account)
        manual_inbox = create(:inbox, account: account)
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        create(:inbox_member, user: agent, inbox: manual_inbox)
        conversation_card = create(
          :kanban_card,
          :conversation_origin,
          kanban_board: kanban_board,
          kanban_stage: earlier_stage,
          conversation: conversation,
          position: 2
        )
        manual_card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: earlier_stage,
          inbox: manual_inbox,
          contact: create(:contact, account: account),
          position: 1
        )
        later_stage_card = create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: later_stage,
          inbox: manual_inbox,
          contact: create(:contact, account: account),
          position: 1
        )

        get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].pluck('id')).to eq([earlier_stage.id, later_stage.id])
        expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([manual_card.id, conversation_card.id])
        expect(response.parsed_body['stages'].second['cards'].pluck('id')).to eq([later_stage_card.id])
      end

      it 'does not query notes during board listing' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        conversation = create(:conversation, account: account)
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        create(:kanban_card, :conversation_origin, account: account, kanban_board: kanban_board, kanban_stage: stage, conversation: conversation)
        create(:note, contact: conversation.contact)

        sql_queries = []
        callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
              headers: agent.create_new_auth_token,
              as: :json
        end

        expect(response).to have_http_status(:success)
        expect(sql_queries.none? { |sql| sql.include?('notes') }).to be(true), 'Board listing should not query the notes table'
        expect(sql_queries.none? { |sql| sql.include?('taggings') }).to be(true), 'Board listing should not query the taggings table'
        expect(sql_queries.none? { |sql| sql.include?('tags') }).to be(true), 'Board listing should not query the tags table'
        expect(sql_queries.none? { |sql| sql.include?('labels') }).to be(true), 'Board listing should not query the labels table'
      end

      it 'does not query notes taggings tags or labels with multiple cards sharing a contact' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        inbox = create(:inbox, account: account)
        contact = create(:contact, account: account)
        create(:inbox_member, user: agent, inbox: inbox)
        create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          contact: contact,
          inbox: inbox,
          subject: 'First opportunity'
        )
        create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          contact: contact,
          inbox: inbox,
          subject: 'Second opportunity'
        )
        create(
          :kanban_card,
          account: account,
          kanban_board: kanban_board,
          kanban_stage: stage,
          contact: contact,
          inbox: inbox,
          subject: 'Third opportunity'
        )
        create(:note, contact: contact)

        sql_queries = []
        callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
              headers: agent.create_new_auth_token,
              as: :json
        end

        expect(response).to have_http_status(:success)
        expect(sql_queries.none? { |sql| sql.include?('notes') }).to be(true)
        expect(sql_queries.none? { |sql| sql.include?('taggings') }).to be(true)
        expect(sql_queries.none? { |sql| sql.include?('tags') }).to be(true)
        expect(sql_queries.none? { |sql| sql.include?('labels') }).to be(true)
      end
    end

    it 'does not read conversation kanban states even when board reads are disabled' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      legacy_conversation = create(:conversation, account: account)
      card_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: legacy_conversation.inbox)
      create(:inbox_member, user: agent, inbox: card_conversation.inbox)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: legacy_conversation
      )
      card = create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: card_conversation)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['use_opportunity_card_reads']).to be(false)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
    end

    it 'keeps reading kanban cards when use_opportunity_card_reads changes' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      legacy_conversation = create(:conversation, account: account)
      card_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: legacy_conversation.inbox)
      create(:inbox_member, user: agent, inbox: card_conversation.inbox)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: legacy_conversation
      )
      card = create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: card_conversation)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body['use_opportunity_card_reads']).to be(false)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])

      kanban_board.update!(use_opportunity_card_reads: true)
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body['use_opportunity_card_reads']).to be(true)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])

      kanban_board.update!(use_opportunity_card_reads: false)
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body['use_opportunity_card_reads']).to be(false)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
    end

    it 'does not let another board flag value change the read source' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      legacy_conversation = create(:conversation, account: account)
      card_conversation = create(:conversation, account: account)
      create(:inbox_member, user: agent, inbox: legacy_conversation.inbox)
      create(:inbox_member, user: agent, inbox: card_conversation.inbox)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: legacy_conversation
      )
      card = create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: card_conversation)
      create(:kanban_board, account: account, use_opportunity_card_reads: true)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards' do
    let(:payload) { { kanban_board: { name: 'Support', description: 'Support funnel', position: 1 } } }

    it 'creates a board for administrators' do
      expect do
        post "/api/v1/accounts/#{account.id}/kanban_boards",
             headers: administrator.create_new_auth_token,
             params: payload,
             as: :json
      end.to change(KanbanBoard, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Support')
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(false)
      expect(response.parsed_body['use_opportunity_card_reads']).to be(true)
      expect(KanbanBoard.last.use_opportunity_card_reads).to be(true)
    end

    it 'accepts automatic card creation setting' do
      post "/api/v1/accounts/#{account.id}/kanban_boards",
           headers: administrator.create_new_auth_token,
           params: { kanban_board: payload[:kanban_board].merge(auto_create_cards_from_conversations: true) },
           as: :json

      expect(response).to have_http_status(:success)
      expect(KanbanBoard.last.auto_create_cards_from_conversations).to be(true)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(true)
    end

    it 'returns unauthorized for agents' do
      post "/api/v1/accounts/#{account.id}/kanban_boards",
           headers: agent.create_new_auth_token,
           params: payload,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'updates a board for administrators' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Updated Sales', active: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.name).to eq('Updated Sales')
      expect(kanban_board).not_to be_active
    end

    it 'updates automatic card creation from false to true' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { auto_create_cards_from_conversations: true } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.auto_create_cards_from_conversations).to be(true)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(true)
    end

    it 'updates automatic card creation from true to false' do
      kanban_board.update!(auto_create_cards_from_conversations: true)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { auto_create_cards_from_conversations: false } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.auto_create_cards_from_conversations).to be(false)
      expect(response.parsed_body['auto_create_cards_from_conversations']).to be(false)
    end

    it 'does not return a default stage id' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Updated Sales' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload.name).to eq('Updated Sales')
      expect(response.parsed_body).not_to have_key('default_stage_id')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/kanban_boards/{id}' do
    it 'deactivates a board for administrators' do
      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
               headers: administrator.create_new_auth_token,
               as: :json
      end.not_to change(KanbanBoard, :count)

      expect(response).to have_http_status(:no_content)
      expect(kanban_board.reload).not_to be_active
    end
  end
end
