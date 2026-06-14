require 'rails_helper'

RSpec.describe 'Kanban Cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: conversation.inbox)
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/cards/manual' do
    let(:manual_contact) { create(:contact, account: account) }
    let(:manual_inbox) { create(:inbox, account: account) }

    before do
      create(:inbox_member, user: agent, inbox: manual_inbox)
    end

    it 'creates a manual card with valid payload' do
      expect do
        post_manual_card
      end.to change(KanbanCard.manual, :count).by(1)

      expect(KanbanCard.last).to have_attributes(
        kanban_stage_id: stage.id,
        contact_id: manual_contact.id,
        inbox_id: manual_inbox.id,
        subject: 'Cotação de notebooks'
      )
    end

    it 'emits kanban.card.created with a compact payload' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_manual_card

      card = KanbanCard.last

      expect(response).to have_http_status(:created)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id, card_id: card.id, conversation_id: nil }
      )
    end

    it 'does not emit kanban.card.created when manual creation fails' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_manual_card(params: manual_card_payload.merge(subject: '  '))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'returns created status' do
      post_manual_card

      expect(response).to have_http_status(:created)
    end

    it 'sets origin as manual server-side' do
      post_manual_card(params: manual_card_payload.merge(origin: 'conversation'))

      expect(KanbanCard.last).to be_manual
      expect(response.parsed_body['origin']).to eq('manual')
    end

    it 'does not create ConversationKanbanState' do
      expect do
        post_manual_card
      end.not_to change(ConversationKanbanState, :count)
    end

    it 'returns the stable card payload' do
      post_manual_card

      expect(response.parsed_body.keys).to include(
        'id', 'origin', 'subject', 'active', 'kanban_stage_id', 'position', 'contact', 'inbox', 'conversation_id', 'conversation',
        'moved_by_id', 'moved_at'
      )
    end

    it 'supports a card without linked conversation' do
      post_manual_card

      expect(response.parsed_body['conversation_id']).to be_nil
      expect(response.parsed_body['conversation']).to be_nil
      expect(response.parsed_body['moved_by_id']).to be_nil
      expect(response.parsed_body['moved_at']).to be_nil
    end

    it 'links the recent permitted conversation when available' do
      matching_conversation = create(:conversation, account: account, contact: manual_contact, inbox: manual_inbox, last_activity_at: 1.day.ago)

      post_manual_card

      expect(response.parsed_body['conversation_id']).to eq(matching_conversation.display_id)
      expect(response.parsed_body['conversation']).to be_present
    end

    it 'rejects blank subject' do
      post_manual_card(params: manual_card_payload.merge(subject: '  '))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include("Subject can't be blank")
    end

    it 'rejects normalized duplicate subject' do
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: manual_contact,
        inbox: manual_inbox,
        subject: 'cotação   de notebooks'
      )

      post_manual_card
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Manual opportunity with this subject already exists')
    end

    it 'rejects stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      post_manual_card(params: manual_card_payload.merge(kanban_stage_id: other_stage.id))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects contact from another account' do
      post_manual_card(params: manual_card_payload.merge(contact_id: create(:contact).id))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects inbox from another account' do
      post_manual_card(params: manual_card_payload.merge(inbox_id: create(:inbox).id))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects inbox not in selected_inboxes scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')

      post_manual_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Inbox is not allowed by board scope')
    end

    it 'accepts inbox when selected in selected_inboxes scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: manual_inbox)

      post_manual_card

      expect(response).to have_http_status(:created)
    end

    it 'rejects inactive stage' do
      stage.update!(active: false)

      post_manual_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Stage must be active')
    end

    it 'creates when opportunity-card reads are disabled' do
      kanban_board.update!(use_opportunity_card_reads: false)

      expect do
        post_manual_card
      end.to change(KanbanCard.manual, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'rejects an agent without inbox access' do
      agent.inbox_members.where(inbox: manual_inbox).destroy_all

      post_manual_card
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('User cannot access inbox')
    end

    it 'allows an admin to create without inbox membership' do
      admin = create(:user, account: account, role: :administrator)
      agent.inbox_members.where(inbox: manual_inbox).destroy_all

      expect do
        post_manual_card(headers: admin.create_new_auth_token)
      end.to change(KanbanCard.manual, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  describe 'stable card ID routes' do
    it 'returns a card detail by stable ID' do
      card = create_manual_card(subject: 'Cotação de notebooks')

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'id' => card.id,
        'subject' => 'Cotação de notebooks',
        'description' => nil,
        'starts_at' => nil,
        'due_at' => nil,
        'conversation_id' => nil,
        'conversation' => nil
      )
    end

    it 'returns stable detail timestamps as ISO8601' do
      starts_at = Time.zone.parse('2026-06-01T09:00:00-03:00')
      due_at = Time.zone.parse('2026-06-05T18:00:00-03:00')
      card = create_manual_card(starts_at: starts_at, due_at: due_at)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['starts_at']).to eq(starts_at.iso8601)
      expect(response.parsed_body['due_at']).to eq(due_at.iso8601)
    end

    it 'returns linked conversation display ID in stable detail' do
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 9,
        moved_by: agent,
        moved_at: 1.hour.ago
      )
      card = create_conversation_card(position: 1)
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.display_id)
      expect(response.parsed_body['conversation']).to be_present
      expect(response.parsed_body['conversation']).to include(
        'id' => conversation.display_id,
        'messages' => be_present
      )
      expect(response.parsed_body['conversation']).to have_key('unread_count')
      expect(response.parsed_body['moved_by_id']).to be_nil
      expect(response.parsed_body['moved_at']).to be_nil
    end

    it 'rejects stable detail for cards from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      card = create_manual_card(kanban_board: other_board, kanban_stage: other_stage)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects unauthorized stable detail cards' do
      hidden_inbox = create(:inbox, account: account)
      card = create_manual_card(inbox: hidden_inbox)

      get "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects stable detail when the board is inactive' do
      card = create_manual_card
      kanban_board.update!(active: false)

      get stable_card_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects stable card routes when the card stage is inactive' do
      card = create_manual_card
      stage.update!(active: false)

      get stable_card_url(card), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Hidden opportunity' } },
            as: :json
      expect(response).to have_http_status(:not_found)

      patch stable_card_url(card, suffix: 'reorder'),
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json
      expect(response).to have_http_status(:not_found)

      delete stable_card_url(card), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'updates a card by stable ID' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_manual_card(position: 1)
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
              headers: agent.create_new_auth_token,
              params: { card: { kanban_stage_id: next_stage.id } },
              as: :json
      end

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(
        kanban_stage_id: next_stage.id,
        position: 1,
        stage_entered_at: Time.zone.parse('2026-06-09 12:00:00 UTC')
      )
      expect(card.stage_entered_at).not_to eq(previous_stage_entered_at)
    end

    it 'rejects stable update when the board is inactive' do
      card = create_manual_card(subject: 'Visible opportunity')
      kanban_board.update!(active: false)

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Hidden opportunity' } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload.subject).to eq('Visible opportunity')
    end

    it 'updates stable scalar card details' do
      card = create_manual_card(subject: 'Old opportunity', description: 'Existing note')
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: {
              card: {
                subject: 'Cotação de notebooks',
                description: 'Anotação única do card',
                starts_at: '2026-06-01T09:00:00-03:00',
                due_at: '2026-06-05T18:00:00-03:00'
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(
        subject: 'Cotação de notebooks',
        description: 'Anotação única do card',
        starts_at: Time.zone.parse('2026-06-01T09:00:00-03:00'),
        due_at: Time.zone.parse('2026-06-05T18:00:00-03:00')
      )
      expect(card.stage_entered_at).to eq(previous_stage_entered_at)
      expect(response.parsed_body['description']).to eq('Anotação única do card')
      expect(response.parsed_body['starts_at']).to eq(card.starts_at.iso8601)
      expect(response.parsed_body['due_at']).to eq(card.due_at.iso8601)
    end

    it 'clears stable card description with blank strings' do
      card = create_manual_card(description: 'Anotação existente')

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { description: '' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.description).to be_nil
      expect(response.parsed_body['description']).to be_nil
    end

    it 'clears stable card description with null' do
      card = create_manual_card(description: 'Anotação existente')

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { description: nil } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.description).to be_nil
      expect(response.parsed_body['description']).to be_nil
    end

    it 'emits kanban.card.updated with a compact payload for scalar updates' do
      card = create_manual_card(subject: 'Old opportunity')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Cotação de notebooks' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_UPDATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id, card_id: card.id, conversation_id: nil }
      )
    end

    it 'updates stable metadata and labels in one request' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:label, account: account, title: 'urgente')
      create(:label, account: account, title: 'vendas')
      card = create_manual_card(subject: 'Old opportunity')
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        patch stable_card_url(card),
              headers: agent.create_new_auth_token,
              params: {
                card: {
                  subject: 'Cliente - Inbox',
                  kanban_stage_id: next_stage.id,
                  due_at: '2026-06-07T18:00:00-03:00',
                  labels: %w[urgente vendas]
                }
              },
              as: :json
      end

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(
        subject: 'Cliente - Inbox',
        kanban_stage_id: next_stage.id,
        due_at: Time.zone.parse('2026-06-07T18:00:00-03:00'),
        stage_entered_at: Time.zone.parse('2026-06-09 12:00:00 UTC')
      )
      expect(card.stage_entered_at).not_to eq(previous_stage_entered_at)
      expect(card.label_list).to contain_exactly('urgente', 'vendas')
    end

    it 'deduplicates stable card labels on metadata update' do
      create(:label, account: account, title: 'urgente')
      card = create_manual_card
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { labels: %w[urgente urgente] } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to contain_exactly('urgente')
      expect(card.stage_entered_at).to eq(previous_stage_entered_at)
    end

    it 'removes all stable card labels when labels is empty' do
      create(:label, account: account, title: 'urgente')
      card = create_manual_card
      card.update_labels(['urgente'])

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { labels: [] } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload.label_list).to be_empty
    end

    it 'rejects unknown stable card labels on metadata update' do
      card = create_manual_card

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { labels: ['unknown'] } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Unknown labels: unknown')
      expect(card.reload.label_list).to be_empty
    end

    it 'rejects stable card labels from another account on metadata update' do
      create(:label, account: create(:account), title: 'external')
      card = create_manual_card

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { labels: ['external'] } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Unknown labels: external')
      expect(card.reload.label_list).to be_empty
    end

    it 'rolls back stable metadata when labels are invalid' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:label, account: account, title: 'urgente')
      card = create_manual_card(subject: 'Old opportunity', due_at: nil)
      card.update_labels(['urgente'])

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: {
              card: {
                subject: 'New opportunity',
                kanban_stage_id: next_stage.id,
                due_at: '2026-06-07T18:00:00-03:00',
                labels: ['unknown']
              }
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload).to have_attributes(subject: 'Old opportunity', kanban_stage_id: stage.id, due_at: nil)
      expect(card.label_list).to contain_exactly('urgente')
    end

    it 'emits kanban.card.updated after successful stable metadata and label update' do
      create(:label, account: account, title: 'urgente')
      card = create_manual_card
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Updated opportunity', labels: ['urgente'] } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_UPDATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id, card_id: card.id, conversation_id: nil }
      )
    end

    it 'does not emit kanban.card.updated when stable label validation fails' do
      card = create_manual_card
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Updated opportunity', labels: ['unknown'] } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_UPDATED,
        anything,
        anything
      )
    end

    it 'clears stable card dates' do
      card = create_manual_card(starts_at: Time.current, due_at: 1.day.from_now)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { starts_at: nil, due_at: nil } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(starts_at: nil, due_at: nil)
      expect(response.parsed_body).to include('starts_at' => nil, 'due_at' => nil)
    end

    it 'accepts equal stable card start and due timestamps' do
      card = create_manual_card

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { starts_at: '2026-06-01T09:00:00-03:00', due_at: '2026-06-01T09:00:00-03:00' } },
            as: :json

      expect(response).to have_http_status(:success)
    end

    it 'rejects stable card due dates before start dates' do
      card = create_manual_card

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { starts_at: '2026-06-05T18:00:00-03:00', due_at: '2026-06-01T09:00:00-03:00' } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Due at must be greater than or equal to starts at')
    end

    it 'does not emit kanban.card.updated when update validation fails' do
      card = create_manual_card
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { starts_at: '2026-06-05T18:00:00-03:00', due_at: '2026-06-01T09:00:00-03:00' } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_UPDATED,
        anything,
        anything
      )
    end

    it 'does not permit stable immutable card fields to be mutated' do
      other_contact = create(:contact, account: account)
      other_inbox = create(:inbox, account: account)
      other_conversation = create(:conversation, account: account)
      card = create_manual_card

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: {
              card: {
                origin: 'conversation',
                contact_id: other_contact.id,
                inbox_id: other_inbox.id,
                conversation_id: other_conversation.display_id
              }
            },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(
        origin: 'manual',
        contact_id: conversation.contact_id,
        inbox_id: conversation.inbox_id,
        conversation_id: nil
      )
    end

    it 'updates normalized subject for manual stable cards' do
      card = create_manual_card(subject: 'Old opportunity')

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { subject: '  Cotação   de notebooks  ' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(subject: 'Cotação de notebooks', normalized_subject: 'cotação de notebooks')
    end

    it 'updates normalized subject for conversation-origin stable cards' do
      card = create_conversation_card(position: 1)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Cotação de notebooks' } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(subject: 'Cotação de notebooks', normalized_subject: 'cotação de notebooks')
    end

    it 'reorders a card by stable ID within the same stage' do
      first_card = create_manual_card(position: 1)
      second_card = create_manual_card(position: 2, subject: 'Second opportunity')
      third_card = create_manual_card(position: 3, subject: 'Third opportunity')
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      third_card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{third_card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(third_card.reload.position).to eq(1)
      expect(third_card.stage_entered_at).to eq(previous_stage_entered_at)
      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'emits kanban.card.reordered with equal source and target stage IDs for same-stage reorder' do
      create_manual_card(position: 1)
      card = create_manual_card(position: 2, subject: 'Second opportunity')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_REORDERED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          card_id: card.id,
          conversation_id: nil,
          source_stage_id: stage.id,
          target_stage_id: stage.id
        }
      )
    end

    it 'reorders a card by stable ID across stages' do
      destination_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      moving_card = create_manual_card(position: 1)
      source_card = create_manual_card(position: 2, subject: 'Source opportunity')
      destination_card = create_manual_card(kanban_stage: destination_stage, position: 1, subject: 'Destination opportunity')
      previous_stage_entered_at = 2.days.ago.change(usec: 0)
      moving_card.update_column(:stage_entered_at, previous_stage_entered_at) # rubocop:disable Rails/SkipsModelValidations

      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{moving_card.id}/reorder",
              headers: agent.create_new_auth_token,
              params: { card: { kanban_stage_id: destination_stage.id, position: 1 } },
              as: :json
      end

      expect(response).to have_http_status(:success)
      expect(moving_card.reload).to have_attributes(
        kanban_stage_id: destination_stage.id,
        position: 1,
        stage_entered_at: Time.zone.parse('2026-06-09 12:00:00 UTC')
      )
      expect(moving_card.stage_entered_at).not_to eq(previous_stage_entered_at)
      expect(source_card.reload.position).to eq(1)
      expect(destination_card.reload.position).to eq(2)
    end

    it 'emits kanban.card.reordered with source and target stage IDs for cross-stage reorder' do
      destination_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_manual_card(position: 1)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: destination_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_REORDERED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          card_id: card.id,
          conversation_id: nil,
          source_stage_id: stage.id,
          target_stage_id: destination_stage.id
        }
      )
    end

    it 'does not emit kanban.card.reordered when reorder fails' do
      card = create_manual_card(position: 1)
      inactive_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, active: false)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: inactive_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_REORDERED,
        anything,
        anything
      )
    end

    it 'rejects stable reorder when the board is inactive' do
      card = create_manual_card(position: 1)
      kanban_board.update!(active: false)

      patch stable_card_url(card, suffix: 'reorder'),
            headers: agent.create_new_auth_token,
            params: { card: { position: 2 } },
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload.position).to eq(1)
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

    it 'emits kanban.card.deleted with a compact payload' do
      card = create_manual_card
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_DELETED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id, card_id: card.id, conversation_id: nil }
      )
    end

    it 'does not emit kanban.card.deleted when delete fails' do
      card = create_manual_card
      kanban_board.update!(active: false)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      delete stable_card_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_DELETED,
        anything,
        anything
      )
    end

    it 'rejects stable delete when the board is inactive' do
      card = create_manual_card
      kanban_board.update!(active: false)

      delete stable_card_url(card), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(card.reload).to be_active
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

    it 'reorders a conversation-origin card without changing legacy state' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      card = create_conversation_card(position: 1)

      expect do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}/reorder",
              headers: agent.create_new_auth_token,
              params: { card: { kanban_stage_id: next_stage.id, position: 1 } },
              as: :json
      end.not_to change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
      expect(state.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end

    it 'emits kanban.card.reordered with conversation_id for conversation-origin cards' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_conversation_card(position: 1)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch stable_card_url(card, suffix: 'reorder'),
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id, position: 1 } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_REORDERED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          card_id: card.id,
          conversation_id: conversation.id,
          source_stage_id: stage.id,
          target_stage_id: next_stage.id
        }
      )
    end

    it 'updates a conversation-origin card without changing legacy state' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      card = create_conversation_card(position: 1)

      expect do
        patch "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
              headers: agent.create_new_auth_token,
              params: { card: { kanban_stage_id: next_stage.id } },
              as: :json
      end.not_to change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:success)
      expect(card.reload).to have_attributes(kanban_stage_id: next_stage.id, position: 1)
      expect(state.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end

    it 'emits kanban.card.updated with conversation_id for conversation-origin cards' do
      next_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card = create_conversation_card(position: 1)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { kanban_stage_id: next_stage.id } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_UPDATED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          stage_id: next_stage.id,
          card_id: card.id,
          conversation_id: conversation.id
        }
      )
    end

    it 'soft-deletes a conversation-origin card without changing legacy state' do
      state = create(
        :conversation_kanban_state,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation,
        position: 1
      )
      card = create_conversation_card(position: 1)

      expect do
        delete "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}",
               headers: agent.create_new_auth_token,
               as: :json
      end.not_to change(ConversationKanbanState, :count)

      expect(response).to have_http_status(:no_content)
      expect(card.reload).not_to be_active
      expect(state.reload).to have_attributes(kanban_stage_id: stage.id, position: 1)
    end

    it 'emits kanban.card.deleted with conversation_id for conversation-origin cards' do
      card = create_conversation_card(position: 1)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      delete stable_card_url(card),
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_DELETED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          stage_id: stage.id,
          card_id: card.id,
          conversation_id: conversation.id
        }
      )
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

    it 'returns 404 for card show when board is not visible to agent' do
      card = create_manual_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      get stable_card_url(card),
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for card update when board is not visible to agent' do
      card = create_manual_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      patch stable_card_url(card),
            headers: agent.create_new_auth_token,
            params: { card: { subject: 'Updated' } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for card destroy when board is not visible to agent' do
      card = create_manual_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      delete stable_card_url(card),
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for card reorder when board is not visible to agent' do
      card = create_manual_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      patch stable_card_url(card, suffix: 'reorder'),
            headers: agent.create_new_auth_token,
            params: { card: { position: 2 } },
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'allows admin card operations on selected_agents board without membership' do
      card = create_manual_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      get stable_card_url(card),
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
    end
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

  def create_conversation_card(attributes = {})
    create(
      :kanban_card,
      :conversation_origin,
      {
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        conversation: conversation
      }.merge(attributes)
    )
  end

  def stable_card_url(target_card, suffix: nil)
    path = "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{target_card.id}"
    suffix.present? ? "#{path}/#{suffix}" : path
  end

  def post_manual_card(params: manual_card_payload, headers: agent.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/manual",
         headers: headers,
         params: { card: params },
         as: :json
  end

  def manual_card_payload
    {
      kanban_stage_id: stage.id,
      contact_id: manual_contact.id,
      inbox_id: manual_inbox.id,
      subject: 'Cotação de notebooks'
    }
  end
end
