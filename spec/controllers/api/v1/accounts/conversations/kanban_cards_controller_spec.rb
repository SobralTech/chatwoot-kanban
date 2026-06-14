require 'rails_helper'

RSpec.describe 'Conversation Kanban Cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva') }
  let(:inbox) { create(:inbox, account: account, name: 'Sales Inbox') }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:kanban_board) { create(:kanban_board, account: account, name: 'Sales', position: 1) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'New', color: 'blue', position: 1) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/{conversation.display_id}/kanban_cards' do
    it 'lists active linked conversation-origin cards' do
      card = create_conversation_card

      request_conversation_kanban_cards

      expect(response).to have_http_status(:success)
      expect(payload_ids).to contain_exactly(card.id)
    end

    it 'lists active linked manual cards' do
      card = create_manual_card(conversation: conversation, subject: 'Renewal')

      request_conversation_kanban_cards

      expect(payload_ids).to contain_exactly(card.id)
      expect(response.parsed_body['payload'].first['origin']).to eq('manual')
    end

    it 'excludes unrelated conversation cards' do
      create_conversation_card
      other_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: stage, conversation: other_conversation)

      request_conversation_kanban_cards

      expect(payload_ids.length).to eq(1)
    end

    it 'excludes inactive cards' do
      create_conversation_card(active: false)

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'excludes cards from inactive boards or stages' do
      inactive_board = create(:kanban_board, account: account, active: false)
      inactive_board_stage = create(:kanban_stage, account: account, kanban_board: inactive_board)
      inactive_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, active: false)
      create(:kanban_card, :conversation_origin, kanban_board: inactive_board, kanban_stage: inactive_board_stage, conversation: conversation)
      create(:kanban_card, :conversation_origin, kanban_board: kanban_board, kanban_stage: inactive_stage, conversation: conversation)

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'excludes unauthorized cards after policy filtering' do
      card = create_conversation_card
      allow(KanbanCardPolicy).to receive(:new).and_call_original
      allow(KanbanCardPolicy).to receive(:new).with(anything, card).and_return(instance_double(KanbanCardPolicy, show?: false))

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'omits card from selected_agents board when agent is not a member' do
      create_conversation_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'keeps card from selected_agents board when agent is a member' do
      create_conversation_card
      kanban_board.update!(visibility_mode: 'selected_agents')
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: agent)

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to be_present
    end

    it 'keeps card from selected_agents board for administrator' do
      create_conversation_card
      kanban_board.update!(visibility_mode: 'selected_agents')

      get conversation_kanban_cards_url(conversation), headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_present
    end

    it 'rejects cross-account conversations' do
      other_conversation = create(:conversation)

      get conversation_kanban_cards_url(other_conversation), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns a compact payload only' do
      label = create(:label, account: account, title: 'urgente', color: '#ff0000', description: nil)
      card = create_conversation_card(due_at: Time.zone.parse('2026-06-07T18:00:00-03:00'))
      card.update_labels(['urgente'])

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to contain_exactly(
        {
          'id' => card.id,
          'origin' => 'conversation',
          'subject' => 'Maria Silva - Sales Inbox',
          'due_at' => card.due_at.iso8601,
          'labels' => [
            { 'id' => label.id, 'title' => 'urgente', 'color' => '#ff0000', 'description' => nil }
          ],
          'kanban_board' => { 'id' => kanban_board.id, 'name' => 'Sales' },
          'kanban_stage' => { 'id' => stage.id, 'name' => 'New', 'color' => 'blue' },
          'conversation_id' => conversation.display_id
        }
      )
      expect(response.parsed_body['payload'].first).not_to have_key('conversation')
      expect(response.parsed_body['payload'].first).not_to have_key('contact')
      expect(response.parsed_body['payload'].first).not_to have_key('inbox')
    end

    it 'returns due_at null and labels empty when absent' do
      create_conversation_card(due_at: nil)

      request_conversation_kanban_cards

      card_payload = response.parsed_body['payload'].first
      expect(card_payload['due_at']).to be_nil
      expect(card_payload['labels']).to eq([])
    end

    it 'does not run label queries per linked card' do
      label = create(:label, account: account, title: 'urgente')
      create_conversation_card.update_labels([label.title])

      single_card_count = labels_tags_taggings_query_count(collect_sql_queries { request_conversation_kanban_cards })

      3.times do |index|
        board = create(:kanban_board, account: account, name: "Sales #{index}", position: index + 2)
        board_stage = create(:kanban_stage, account: account, kanban_board: board, position: 1)
        create_conversation_card(kanban_board: board, kanban_stage: board_stage).update_labels([label.title])
      end

      multiple_cards_count = labels_tags_taggings_query_count(collect_sql_queries { request_conversation_kanban_cards })

      expect(multiple_cards_count).to be <= single_card_count + 1
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{conversation.display_id}/kanban_cards' do
    it 'creates a conversation-origin card at position 1' do
      expect do
        post_conversation_kanban_card
      end.to change(KanbanCard.conversation, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last).to have_attributes(origin: 'conversation', position: 1)
    end

    it 'shifts existing active cards by one' do
      existing_card = create_manual_card(position: 1)

      post_conversation_kanban_card

      expect(existing_card.reload.position).to eq(2)
    end

    it 'uses conversation contact and inbox' do
      post_conversation_kanban_card

      expect(KanbanCard.last).to have_attributes(contact_id: contact.id, inbox_id: inbox.id)
    end

    it 'uses the default subject' do
      post_conversation_kanban_card(params: valid_card_payload.except(:subject))

      expect(KanbanCard.last.subject).to eq('Maria Silva - Sales Inbox')
      expect(response.parsed_body['payload']['subject']).to eq('Maria Silva - Sales Inbox')
    end

    it 'accepts a custom trimmed subject' do
      post_conversation_kanban_card(params: valid_card_payload.merge(subject: '  Enterprise   renewal  '))

      expect(KanbanCard.last.subject).to eq('Enterprise renewal')
      expect(response.parsed_body['payload']['subject']).to eq('Enterprise renewal')
    end

    it 'accepts due_at ISO8601' do
      post_conversation_kanban_card(params: valid_card_payload.merge(due_at: '2026-06-07T18:00:00-03:00'))

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last.due_at).to eq(Time.zone.parse('2026-06-07T18:00:00-03:00'))
    end

    it 'accepts due_at null' do
      post_conversation_kanban_card(params: valid_card_payload.merge(due_at: nil))

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last.due_at).to be_nil
    end

    it 'persists existing labels' do
      create(:label, account: account, title: 'urgente')
      create(:label, account: account, title: 'vendas')

      post_conversation_kanban_card(params: valid_card_payload.merge(labels: %w[urgente vendas]))

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last.label_list).to contain_exactly('urgente', 'vendas')
    end

    it 'accepts empty labels' do
      post_conversation_kanban_card(params: valid_card_payload.merge(labels: []))

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last.label_list).to be_empty
    end

    it 'deduplicates labels' do
      create(:label, account: account, title: 'urgente')

      post_conversation_kanban_card(params: valid_card_payload.merge(labels: %w[urgente urgente]))

      expect(response).to have_http_status(:created)
      expect(KanbanCard.last.label_list).to contain_exactly('urgente')
    end

    it 'rejects a missing label without creating a card' do
      expect do
        post_conversation_kanban_card(params: valid_card_payload.merge(labels: ['missing']))
      end.not_to change(KanbanCard, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Labels must exist in account')
    end

    it 'rejects a label from another account' do
      create(:label, title: 'external')

      post_conversation_kanban_card(params: valid_card_payload.merge(labels: ['external']))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Labels must exist in account')
    end

    it 'rejects duplicate historical cards including inactive duplicates' do
      create_conversation_card(active: false, subject: 'Maria Silva - Sales Inbox')

      post_conversation_kanban_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Conversation already has an opportunity with this subject on this board')
    end

    it 'rejects an invalid board' do
      post_conversation_kanban_card(params: valid_card_payload.merge(kanban_board_id: create(:kanban_board).id))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects board not visible to agent' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      post_conversation_kanban_card

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects board when inbox is not in selected_inboxes scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')

      post_conversation_kanban_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Conversation inbox is not allowed by board scope')
    end

    it 'accepts board when inbox is selected in selected_inboxes scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      post_conversation_kanban_card

      expect(response).to have_http_status(:created)
    end

    it 'rejects a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      post_conversation_kanban_card(params: valid_card_payload.merge(kanban_stage_id: other_stage.id))

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects inactive boards or stages' do
      kanban_board.update!(active: false)
      post_conversation_kanban_card

      expect(response).to have_http_status(:not_found)

      kanban_board.update!(active: true)
      stage.update!(active: false)
      post_conversation_kanban_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Stage must be active')
    end

    it 'rejects unauthorized conversation or inbox access' do
      agent.inbox_members.destroy_all

      post_conversation_kanban_card

      expect(response).to have_http_status(:unauthorized)
    end

    it 'emits kanban.card.created only after successful creation' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_conversation_kanban_card

      card = KanbanCard.last
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
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

    it 'does not emit kanban.card.created on failure' do
      create_conversation_card(subject: 'Maria Silva - Sales Inbox')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_conversation_kanban_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'does not emit kanban.card.created when labels are invalid' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_conversation_kanban_card(params: valid_card_payload.merge(labels: ['missing']))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end
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

  def create_manual_card(attributes = {})
    create(
      :kanban_card,
      {
        account: account,
        kanban_board: kanban_board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox
      }.merge(attributes)
    )
  end

  def request_conversation_kanban_cards
    get conversation_kanban_cards_url(conversation), headers: agent.create_new_auth_token, as: :json
  end

  def post_conversation_kanban_card(params: valid_card_payload)
    post conversation_kanban_cards_url(conversation), headers: agent.create_new_auth_token, params: { card: params }, as: :json
  end

  def conversation_kanban_cards_url(target_conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{target_conversation.display_id}/kanban_cards"
  end

  def valid_card_payload
    {
      kanban_board_id: kanban_board.id,
      kanban_stage_id: stage.id,
      subject: nil
    }
  end

  def payload_ids
    response.parsed_body['payload'].map { |card| card['id'] }
  end

  def collect_sql_queries(&)
    sql_queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      sql_queries << sql if sql.present? && payload[:name] != 'SCHEMA'
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    sql_queries
  end

  def labels_tags_taggings_query_count(sql_queries)
    sql_queries.count do |sql|
      sql.match?(/FROM "labels"|JOIN "labels"|FROM "tags"|JOIN "tags"|FROM "taggings"|JOIN "taggings"/)
    end
  end
end
