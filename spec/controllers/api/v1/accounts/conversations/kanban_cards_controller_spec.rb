require 'rails_helper'

RSpec.describe 'Conversation Kanban Cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
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

    it 'rejects cross-account conversations' do
      other_conversation = create(:conversation)

      get conversation_kanban_cards_url(other_conversation), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns a compact payload only' do
      card = create_conversation_card

      request_conversation_kanban_cards

      expect(response.parsed_body['payload']).to contain_exactly(
        {
          'id' => card.id,
          'origin' => 'conversation',
          'subject' => 'Maria Silva - Sales Inbox',
          'kanban_board' => { 'id' => kanban_board.id, 'name' => 'Sales' },
          'kanban_stage' => { 'id' => stage.id, 'name' => 'New', 'color' => 'blue' },
          'conversation_id' => conversation.display_id
        }
      )
      expect(response.parsed_body['payload'].first).not_to have_key('conversation')
      expect(response.parsed_body['payload'].first).not_to have_key('contact')
      expect(response.parsed_body['payload'].first).not_to have_key('inbox')
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

    it 'rejects duplicate historical cards including inactive duplicates' do
      create_conversation_card(active: false)

      post_conversation_kanban_card

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Conversation already has an opportunity on this board')
    end

    it 'rejects an invalid board' do
      post_conversation_kanban_card(params: valid_card_payload.merge(kanban_board_id: create(:kanban_board).id))

      expect(response).to have_http_status(:not_found)
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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Board must be active')

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
        { account_id: account.id, board_id: kanban_board.id, stage_id: stage.id, card_id: card.id }
      )
    end

    it 'does not emit kanban.card.created on failure' do
      create_conversation_card
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post_conversation_kanban_card

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
end
