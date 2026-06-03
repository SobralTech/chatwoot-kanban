require 'rails_helper'

RSpec.describe 'Kanban stage cards API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/{account.id}/kanban_boards/{kanban_board.id}/stages/{kanban_stage.id}/cards' do
    it 'returns the first page of cards' do
      cards = create_visible_cards(3)

      get stage_cards_path, headers: agent.create_new_auth_token, params: { limit: 2 }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stage_id']).to eq(kanban_stage.id)
      expect(response.parsed_body['cards'].pluck('id')).to eq(cards.first(2).pluck(:id))
      expect(response.parsed_body['pagination']).to include(
        'limit' => 2,
        'has_more' => true,
        'next_cursor' => { 'after_id' => cards.second.id },
        'total_count' => 3
      )
    end

    it 'returns the next page from a cursor' do
      cards = create_visible_cards(4)

      get stage_cards_path,
          headers: agent.create_new_auth_token,
          params: { limit: 2, cursor: { after_id: cards.second.id } },
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cards'].pluck('id')).to eq(cards.last(2).pluck(:id))
      expect(response.parsed_body['pagination']).to include(
        'limit' => 2,
        'has_more' => false,
        'next_cursor' => nil,
        'total_count' => 4
      )
    end

    it 'uses the compact card payload' do
      card = create_visible_card(position: 1, subject: 'Expansion opportunity')

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      response_card = response.parsed_body['cards'].first
      expect(response).to have_http_status(:success)
      expect(response_card.keys).to match_array(compact_card_keys)
      expect(response_card).to include(
        'id' => card.id,
        'kanban_stage_id' => kanban_stage.id,
        'position' => 1,
        'origin' => 'manual',
        'subject' => 'Expansion opportunity',
        'active' => true,
        'conversation_id' => nil,
        'moved_by_id' => nil,
        'moved_at' => nil
      )
      expect(response_card).not_to include('conversation', 'messages', 'unread_count')
      expect(response_card['contact']).to include('id' => card.contact_id)
      expect(response_card['inbox']).to include('id' => inbox.id)
    end

    it 'uses a default limit of 20' do
      cards = create_visible_cards(21)

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cards'].pluck('id')).to eq(cards.first(20).pluck(:id))
      expect(response.parsed_body['pagination']).to include('limit' => 20, 'has_more' => true, 'total_count' => 21)
    end

    it 'clamps limit to 50' do
      cards = create_visible_cards(51)

      get stage_cards_path, headers: agent.create_new_auth_token, params: { limit: 100 }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cards'].pluck('id')).to eq(cards.first(50).pluck(:id))
      expect(response.parsed_body['pagination']).to include('limit' => 50, 'has_more' => true, 'total_count' => 51)
    end

    it 'excludes inactive cards' do
      active_card = create_visible_card(position: 1)
      create_visible_card(position: 2, active: false)

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cards'].pluck('id')).to eq([active_card.id])
      expect(response.parsed_body['pagination']['total_count']).to eq(1)
    end

    it 'excludes unauthorized cards' do
      visible_card = create_visible_card(position: 1)
      unauthorized_inbox = create(:inbox, account: account)
      create_visible_card(position: 2, inbox: unauthorized_inbox)

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cards'].pluck('id')).to eq([visible_card.id])
      expect(response.parsed_body['pagination']['total_count']).to eq(1)
    end

    it 'rejects inactive boards' do
      kanban_board.update!(active: false)

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects inactive stages' do
      kanban_stage.update!(active: false)

      get stage_cards_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects stages from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      get stage_cards_path(stage: other_stage), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns refresh_required for invalid cursors' do
      get stage_cards_path,
          headers: agent.create_new_auth_token,
          params: { cursor: { after_id: -1 } },
          as: :json

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'refresh_required')
    end

    it 'does not query messages notes labels tags or taggings' do
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        position: 1
      )
      create(:message, account: account, inbox: inbox, conversation: conversation)
      create(:note, contact: contact)
      contact.add_labels(['enterprise'])

      sql_queries = collect_sql_queries { get stage_cards_path, headers: agent.create_new_auth_token, as: :json }
      query_counts = stage_cards_query_counts(sql_queries)

      expect(response).to have_http_status(:success)
      expect(query_counts.slice(:messages, :notes, :labels_tags_taggings)).to eq(messages: 0, notes: 0, labels_tags_taggings: 0)
    end
  end

  def stage_cards_path(stage: kanban_stage)
    "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/stages/#{stage.id}/cards"
  end

  def create_visible_cards(count)
    Array.new(count) do |index|
      create_visible_card(position: index + 1, created_at: (count - index).minutes.ago, subject: "Card #{index}")
    end
  end

  def create_visible_card(attributes = {})
    create(
      :kanban_card,
      {
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: create(:contact, account: account),
        inbox: inbox,
        subject: SecureRandom.hex,
        position: 1
      }.merge(attributes)
    )
  end

  def compact_card_keys
    %w[id kanban_stage_id position origin subject active contact inbox conversation_id moved_by_id moved_at]
  end

  def collect_sql_queries(&)
    sql_queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == 'SCHEMA'
      next if payload[:sql].blank?

      sql_queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    sql_queries
  end

  def stage_cards_query_counts(sql_queries)
    {
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
end
