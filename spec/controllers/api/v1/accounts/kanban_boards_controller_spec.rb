require 'rails_helper'

RSpec.describe 'Kanban Boards API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:kanban_board) { create(:kanban_board, account: account, name: 'Sales') }

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
      expect(response.parsed_body.first).not_to have_key('use_opportunity_card_reads')
    end

    it 'does not return inactive boards' do
      create(:kanban_board, account: account, active: false)

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('active')).to all be(true)
    end

    it 'filters selected_agents boards for non-member agents' do
      create(:kanban_board, account: account, visibility_mode: 'selected_agents', name: 'Restricted')

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('name')).not_to include('Restricted')
    end

    it 'includes selected_agents boards for member agents' do
      restricted_board = create(:kanban_board, account: account, visibility_mode: 'selected_agents', name: 'Restricted')
      create(:kanban_board_member, account: account, kanban_board: restricted_board, user: agent)

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('name')).to include('Restricted')
    end

    it 'shows all boards for administrators regardless of visibility' do
      create(:kanban_board, account: account, visibility_mode: 'selected_agents', name: 'Restricted')

      get "/api/v1/accounts/#{account.id}/kanban_boards",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('name')).to include('Restricted')
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
      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
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

    it 'embeds only the first 20 cards with count and pagination metadata' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: inbox)
      cards = create_board_listing_manual_cards(stage, inbox, 21)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      response_stage = response.parsed_body['stages'].first
      expect(response).to have_http_status(:success)
      expect(response_stage['cards'].pluck('id')).to eq(cards.first(20).pluck(:id))
      expect(response_stage['cards_count']).to eq(21)
      expect(response_stage['pagination']).to include(
        'limit' => 20,
        'has_more' => true,
        'next_cursor' => { 'after_id' => cards[19].id }
      )
    end

    it 'returns inbox scope metadata for the board header' do
      inbox = create(:inbox, account: account)
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['inbox_scope_mode']).to eq('selected_inboxes')
      expect(response.parsed_body['allowed_inbox_ids']).to eq([inbox.id])
    end

    it 'filters embedded cards and counts by inbox ids' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      first_inbox = create(:inbox, account: account)
      second_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: first_inbox)
      create(:inbox_member, user: agent, inbox: second_inbox)
      create_board_listing_manual_cards(stage, first_inbox, 1)
      filtered_cards = create_board_listing_manual_cards(stage, second_inbox, 2)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          params: { inbox_ids: [second_inbox.id] },
          as: :json

      response_stage = response.parsed_body['stages'].first
      expect(response).to have_http_status(:success)
      expect(response_stage['cards'].pluck('id')).to eq(filtered_cards.pluck(:id))
      expect(response_stage['cards_count']).to eq(2)
    end

    it 'keeps historical cards visible without an explicit inbox filter' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      allowed_inbox = create(:inbox, account: account)
      historical_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: allowed_inbox)
      create(:inbox_member, user: agent, inbox: historical_inbox)
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: allowed_inbox)
      allowed_card = create_board_listing_manual_cards(stage, allowed_inbox, 1).first
      historical_card = create_board_listing_manual_cards(stage, historical_inbox, 1).first

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to contain_exactly(allowed_card.id, historical_card.id)
    end

    it 'rejects inbox ids from another account' do
      other_inbox = create(:inbox)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          params: { inbox_ids: [other_inbox.id] },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns has_more false for stages with at most 20 cards' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: inbox)
      create_board_listing_manual_cards(stage, inbox, 20)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      response_stage = response.parsed_body['stages'].first
      expect(response).to have_http_status(:success)
      expect(response_stage['cards'].length).to eq(20)
      expect(response_stage['pagination']).to include('limit' => 20, 'has_more' => false, 'next_cursor' => nil)
    end

    it 'does not load every active card in the board' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: inbox)
      create_board_listing_manual_cards(stage, inbox, 30)

      sql_queries = collect_sql_queries_for_board_listing
      rendered_card_ids = response.parsed_body['stages'].first['cards'].pluck('id')
      card_load_queries = sql_queries.select do |sql|
        sql.match?(/SELECT .*FROM "kanban_cards"/) && sql.exclude?('COUNT')
      end

      expect(response).to have_http_status(:success)
      expect(rendered_card_ids.length).to eq(20)
      expect(response.parsed_body['stages'].first['cards_count']).to eq(30)
      expect(card_load_queries).to include(match(/SELECT "kanban_cards"\."id".*LIMIT/))
      expect(card_load_queries).to include(match(/WHERE "kanban_cards"\."id" IN \((\$\d+, ){19}\$\d+\)/))
    end

    context 'when reading kanban cards' do
      it 'returns active conversation-origin kanban cards with the compact frontend payload' do
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
        expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
        expect(response_card.keys).to match_array(compact_card_keys)
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
        expect(response_card).not_to include('conversation', 'messages', 'unread_count')
        expect(response_card['contact']).to include('id' => conversation.contact.id)
        expect(response_card['inbox']).to include('id' => conversation.inbox.id)
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
          'moved_by_id' => nil,
          'moved_at' => nil
        )
        expect(response_card.keys).to match_array(compact_card_keys)
        expect(response_card).not_to have_key('conversation')
        expect(response_card['contact']['id']).to eq(contact.id)
        expect(response_card['inbox']['id']).to eq(inbox.id)
      end

      it 'returns active manual kanban cards with optional conversation display IDs' do
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
        expect(response_card).not_to have_key('conversation')
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

      it 'does not run inbox or team authorization queries per card' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        inbox = create(:inbox, account: account)
        team = create(:team, account: account)
        create(:inbox_member, user: agent, inbox: inbox)
        create(:team_member, user: agent, team: team)

        3.times do |index|
          create(
            :kanban_card,
            account: account,
            kanban_board: kanban_board,
            kanban_stage: stage,
            inbox: inbox,
            contact: create(:contact, account: account),
            subject: "Manual card #{index}"
          )
        end
        create_list(:conversation, 3, :with_team, account: account, team: team).each do |conversation|
          create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: conversation)
        end

        auth_queries = authorization_membership_queries_for_board_listing

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].length).to eq(6)
        expect(auth_queries.count { |sql| sql.include?('inbox_members') }).to eq(1)
        expect(auth_queries.count { |sql| sql.include?('team_members') }).to eq(1)
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

      it 'does not query messages during board listing' do
        stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
        conversation = create(:conversation, account: account)
        create(:inbox_member, user: agent, inbox: conversation.inbox)
        create(:kanban_card, :conversation_origin, account: account, kanban_board: kanban_board, kanban_stage: stage, conversation: conversation)
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation)

        sql_queries = []
        callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
              headers: agent.create_new_auth_token,
              as: :json
        end

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['stages'].first['cards'].first).not_to have_key('conversation')
        expect(sql_queries.none? { |sql| sql.include?('FROM "messages"') }).to be(true), 'Board listing should not query messages'
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

      it 'keeps board listing query categories bounded with mixed active card visibility' do
        expected_card_ids = create_query_budget_board_listing_cards

        sql_queries = collect_sql_queries_for_board_listing
        query_counts = board_listing_query_counts(sql_queries)

        rendered_card_ids = response.parsed_body['stages'].flat_map { |stage| stage['cards'].pluck('id') }
        expect(response).to have_http_status(:success)
        expect(rendered_card_ids).to match_array(expected_card_ids)
        expect([rendered_card_ids.length, rendered_card_ids.intersect?(inactive_kanban_card_ids)]).to eq([30, false])
        expect(query_counts.slice(:messages, :notes, :labels_tags_taggings)).to eq(messages: 0, notes: 0, labels_tags_taggings: 0)
        expect(query_counts[:kanban_cards]).to be <= 9
        expect(query_counts[:inbox_members]).to be <= 1
        expect(query_counts[:team_members]).to be <= 1
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
      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])
    end

    it 'keeps reading kanban cards when the stored opportunity-card read value changes' do
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

      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])

      kanban_board.update!(use_opportunity_card_reads: true)
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
      expect(response.parsed_body['stages'].first['cards'].pluck('id')).to eq([card.id])

      kanban_board.update!(use_opportunity_card_reads: false)
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
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

    it 'returns 404 for agent without membership on selected_agents board' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'allows agent with membership on selected_agents board' do
      kanban_board.update!(visibility_mode: 'selected_agents')
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: agent)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
    end

    it 'allows administrator on selected_agents board without membership' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
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
      expect(response.parsed_body).not_to have_key('use_opportunity_card_reads')
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

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards/{id}/settings' do
    it 'returns settings for administrators' do
      kanban_board.update!(
        description: 'Pipeline comercial',
        visibility_mode: 'selected_agents',
        inbox_scope_mode: 'selected_inboxes',
        auto_create_cards_from_conversations: true
      )
      inbox = create(:inbox, account: account)
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: agent)
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'id' => kanban_board.id,
        'name' => 'Sales',
        'description' => 'Pipeline comercial',
        'visibility_mode' => 'selected_agents',
        'visible_user_ids' => [agent.id],
        'inbox_scope_mode' => 'selected_inboxes',
        'allowed_inbox_ids' => [inbox.id],
        'auto_create_cards_from_conversations' => true
      )
      expect(response.parsed_body).not_to include('visible_users', 'allowed_inboxes')
    end

    it 'rejects agents' do
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{id}/settings' do
    let(:inbox) { create(:inbox, account: account) }
    let(:second_agent) { create(:user, account: account, role: :agent) }

    it 'updates board basics' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                name: 'Vendas',
                description: 'Pipeline comercial',
                auto_create_cards_from_conversations: true
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload).to have_attributes(
        name: 'Vendas',
        description: 'Pipeline comercial',
        auto_create_cards_from_conversations: true
      )
    end

    it 'replaces memberships' do
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: agent)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                visibility_mode: 'selected_agents',
                visible_user_ids: [second_agent.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload).to be_selected_agents
      expect(kanban_board.kanban_board_members.pluck(:user_id)).to eq([second_agent.id])
      expect(response.parsed_body['visible_user_ids']).to eq([second_agent.id])
    end

    it 'replaces inboxes' do
      old_inbox = create(:inbox, account: account)
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: old_inbox)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                inbox_scope_mode: 'selected_inboxes',
                allowed_inbox_ids: [inbox.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload).to be_selected_inboxes
      expect(kanban_board.kanban_board_inboxes.pluck(:inbox_id)).to eq([inbox.id])
      expect(response.parsed_body['allowed_inbox_ids']).to eq([inbox.id])
    end

    it 'cleans associations when using all_agents and all_inboxes' do
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: agent)
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                visibility_mode: 'all_agents',
                inbox_scope_mode: 'all_inboxes'
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.reload).to be_all_agents
      expect(kanban_board).to be_all_inboxes
      expect(kanban_board.kanban_board_members).to be_empty
      expect(kanban_board.kanban_board_inboxes).to be_empty
    end

    it 'deduplicates selected user and inbox ids' do
      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                visibility_mode: 'selected_agents',
                visible_user_ids: [agent.id, agent.id, second_agent.id],
                inbox_scope_mode: 'selected_inboxes',
                allowed_inbox_ids: [inbox.id, inbox.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(kanban_board.kanban_board_members.order(:user_id).pluck(:user_id)).to eq([agent.id, second_agent.id].sort)
      expect(kanban_board.kanban_board_inboxes.pluck(:inbox_id)).to eq([inbox.id])
    end

    it 'rejects users from another account' do
      other_user = create(:user, account: create(:account), role: :agent)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                visibility_mode: 'selected_agents',
                visible_user_ids: [other_user.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(kanban_board.reload).to be_all_agents
      expect(kanban_board.kanban_board_members).to be_empty
    end

    it 'rejects inboxes from another account' do
      other_inbox = create(:inbox, account: create(:account))

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                inbox_scope_mode: 'selected_inboxes',
                allowed_inbox_ids: [other_inbox.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(kanban_board.reload).to be_all_inboxes
      expect(kanban_board.kanban_board_inboxes).to be_empty
    end

    it 'rolls back all changes when association validation fails' do
      other_inbox = create(:inbox, account: create(:account))

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                name: 'Vendas',
                inbox_scope_mode: 'selected_inboxes',
                allowed_inbox_ids: [other_inbox.id]
              }
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(kanban_board.reload).to have_attributes(name: 'Sales', inbox_scope_mode: 'all_inboxes')
    end

    it 'emits kanban.board.updated after success' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Vendas' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id }
      )
    end

    it 'does not emit kanban.board.updated after failure' do
      other_user = create(:user, account: create(:account), role: :agent)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { visibility_mode: 'selected_agents', visible_user_ids: [other_user.id] } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        anything,
        anything
      )
    end

    it 'preserves historical cards when inbox scope changes' do
      stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, inbox: inbox)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/settings",
            headers: administrator.create_new_auth_token,
            params: {
              kanban_board: {
                inbox_scope_mode: 'selected_inboxes',
                allowed_inbox_ids: []
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to be_active
      expect(card.kanban_board_id).to eq(kanban_board.id)
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

    it 'emits kanban.board.updated with a compact payload' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Updated Sales' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id }
      )
    end

    it 'does not emit kanban.board.updated when update validation fails' do
      create(:kanban_board, account: account, name: 'Support')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
            headers: administrator.create_new_auth_token,
            params: { kanban_board: { name: 'Support' } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        anything,
        anything
      )
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

  def create_query_budget_board_listing_cards
    context = query_budget_board_listing_context

    create_query_budget_access(context)
    expected_card_ids = create_query_budget_visible_cards(context)
    create_query_budget_hidden_records(context, expected_card_ids)

    expected_card_ids
  end

  def create_board_listing_manual_cards(stage, inbox, count)
    Array.new(count) do |index|
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: create(:contact, account: account),
        inbox: inbox,
        subject: "Manual card #{index}",
        position: index + 1
      )
    end
  end

  def query_budget_board_listing_context
    {
      direct_inbox: create(:inbox, account: account),
      team_inbox: create(:inbox, account: account),
      team: create(:team, account: account),
      shared_contact: create(:contact, account: account),
      stages: create_query_budget_stages
    }
  end

  def create_query_budget_access(context)
    create(:inbox_member, user: agent, inbox: context[:direct_inbox])
    create(:team_member, user: agent, team: context[:team])
  end

  def create_query_budget_visible_cards(context)
    expected_card_ids = []
    expected_card_ids.concat(create_direct_manual_cards(context[:stages].first, context[:direct_inbox], context[:shared_contact]))
    expected_card_ids.concat(create_linked_manual_cards(context[:stages].first, context[:direct_inbox], context[:shared_contact]))
    expected_card_ids.concat(create_direct_conversation_cards(context[:stages].second, context[:direct_inbox]))
    expected_card_ids.concat(create_team_conversation_cards(context[:stages].third, context[:team_inbox], context[:team]))
    expected_card_ids
  end

  def create_query_budget_stages
    [
      create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1),
      create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2),
      create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
    ]
  end

  def create_direct_manual_cards(stage, inbox, contact)
    Array.new(5) do |index|
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox,
        subject: "Direct manual card #{index}",
        position: index + 1
      ).id
    end
  end

  def create_linked_manual_cards(stage, inbox, contact)
    Array.new(5) do |index|
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox,
        conversation: conversation,
        subject: "Linked manual card #{index}",
        position: index + 6
      ).id
    end
  end

  def create_direct_conversation_cards(stage, inbox)
    Array.new(10) do |index|
      conversation = create(:conversation, account: account, inbox: inbox)
      create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: index + 1
      ).id
    end
  end

  def create_team_conversation_cards(stage, inbox, team)
    Array.new(10) do |index|
      conversation = create(:conversation, :with_team, account: account, inbox: inbox, team: team)
      create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: index + 1
      ).id
    end
  end

  def create_query_budget_hidden_records(context, expected_card_ids)
    create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: context[:stages].first,
                         contact: context[:shared_contact], inbox: context[:direct_inbox],
                         subject: 'Inactive manual card', active: false)
    create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: context[:stages].first,
                         contact: create(:contact, account: account), inbox: create(:inbox, account: account),
                         subject: 'Unauthorized manual card')
    create(:message, account: account, inbox: context[:direct_inbox], conversation: KanbanCard.find(expected_card_ids[10]).conversation)
    create(:note, contact: context[:shared_contact])
    context[:shared_contact].add_labels(['enterprise'])
  end

  def inactive_kanban_card_ids
    KanbanCard.where(active: false).pluck(:id)
  end

  def board_listing_query_counts(sql_queries)
    {
      kanban_cards: sql_queries.count { |sql| sql.match?(/FROM "kanban_cards"|JOIN "kanban_cards"/) },
      inbox_members: sql_queries.count { |sql| sql.match?(/FROM "inbox_members"|JOIN "inbox_members"/) },
      team_members: sql_queries.count { |sql| sql.match?(/FROM "team_members"|JOIN "team_members"/) },
      messages: sql_queries.count { |sql| sql.match?(/FROM "messages"|JOIN "messages"/) },
      notes: sql_queries.count { |sql| sql.match?(/FROM "notes"|JOIN "notes"/) },
      labels_tags_taggings: labels_tags_taggings_query_count(sql_queries)
    }
  end

  def labels_tags_taggings_query_count(sql_queries)
    sql_queries.count do |sql|
      sql.match?(/FROM "labels"|JOIN "labels"|FROM "tags"|JOIN "tags"|FROM "taggings"|JOIN "taggings"/)
    end
  end

  def compact_card_keys
    %w[id kanban_stage_id position origin subject active contact inbox conversation_id moved_by_id moved_at]
  end

  def authorization_membership_queries_for_board_listing
    collect_sql_queries_for_board_listing.grep(/inbox_members|team_members/)
  end

  def collect_sql_queries_for_board_listing
    sql_queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == 'SCHEMA'
      next if payload[:sql].blank?

      sql_queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}",
          headers: agent.create_new_auth_token,
          as: :json
    end

    sql_queries
  end
end
