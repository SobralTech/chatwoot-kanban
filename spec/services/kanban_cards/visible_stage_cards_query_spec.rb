require 'rails_helper'

RSpec.describe KanbanCards::VisibleStageCardsQuery do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe '#call' do
    it 'returns ordered visible cards' do
      third_card = create_visible_card(position: 2, created_at: 2.hours.ago, subject: 'Third')
      second_card = create_visible_card(position: 1, created_at: 1.hour.ago, subject: 'Second')
      first_card = create_visible_card(position: 1, created_at: 2.hours.ago, subject: 'First')

      result = query.call

      expect(result.cards).to eq([first_card, second_card, third_card])
      expect(result.total_count).to eq(3)
    end

    it 'uses a default limit of 20' do
      cards = create_visible_cards(21)

      result = query.call

      expect(result.cards).to eq(cards.first(20))
      expect(result.has_more).to be(true)
    end

    it 'clamps limit to 50' do
      cards = create_visible_cards(51)

      result = query(limit: 100).call

      expect(result.cards).to eq(cards.first(50))
      expect(result.has_more).to be(true)
    end

    it 'returns has_more and next_cursor' do
      cards = create_visible_cards(3)

      result = query(limit: 2).call

      expect(result.cards).to eq(cards.first(2))
      expect(result.has_more).to be(true)
      expect(result.next_cursor).to eq({ after_id: cards.second.id })
    end

    it 'returns cards after after_id' do
      cards = create_visible_cards(4)

      result = query(limit: 2, cursor: { after_id: cards.second.id }).call

      expect(result.cards).to eq(cards.last(2))
      expect(result.has_more).to be(false)
      expect(result.next_cursor).to be_nil
    end

    it 'excludes inactive cards' do
      active_card = create_visible_card(position: 1)
      create_visible_card(position: 2, active: false)

      result = query.call
      expect(result.cards).to eq([active_card])
    end

    it 'excludes unauthorized cards' do
      visible_card = create_visible_card(position: 1)
      unauthorized_inbox = create(:inbox, account: account)
      create_visible_card(position: 2, inbox: unauthorized_inbox)

      result = query.call
      expect(result.cards).to eq([visible_card])
    end

    it 'raises refresh-required error when cursor anchor is missing' do
      expect { query(cursor: { after_id: -1 }).call }.to raise_error(described_class::RefreshRequiredError)
    end

    it 'raises refresh-required error when cursor anchor moved to another stage' do
      card = create_visible_card(position: 1)
      other_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      card.update!(kanban_stage: other_stage)

      expect { query(cursor: { after_id: card.id }).call }.to raise_error(described_class::RefreshRequiredError)
    end

    it 'raises refresh-required error when cursor anchor is inactive' do
      card = create_visible_card(position: 1)
      card.update!(active: false)

      expect { query(cursor: { after_id: card.id }).call }.to raise_error(described_class::RefreshRequiredError)
    end

    it 'keeps query count bounded with 30 cards' do
      create_visible_cards(30)

      sql_queries = collect_sql_queries { query.call }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:kanban_cards]).to be <= 3
      expect(query_counts[:inbox_members]).to be <= 1
      expect(query_counts[:team_members]).to be <= 1
    end

    it 'keeps compact payload contact avatar queries bounded at the default page size' do
      create_visible_cards_with_contact_avatars(20)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:active_storage_attachments]).to be <= 2
      expect(query_counts[:active_storage_blobs]).to be <= 2
    end

    it 'keeps compact payload contact avatar queries bounded at the max page size' do
      create_visible_cards_with_contact_avatars(50)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies(limit: 50) }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:active_storage_attachments]).to be <= 2
      expect(query_counts[:active_storage_blobs]).to be <= 2
    end

    it 'keeps compact payload inbox avatar queries bounded at the default page size' do
      create_visible_cards_with_inbox_avatars(20)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:active_storage_attachments]).to be <= 2
      expect(query_counts[:active_storage_blobs]).to be <= 2
    end

    it 'keeps compact payload inbox avatar queries bounded at the max page size' do
      create_visible_cards_with_inbox_avatars(50)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies(limit: 50) }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:active_storage_attachments]).to be <= 2
      expect(query_counts[:active_storage_blobs]).to be <= 2
    end

    it 'keeps compact payload inbox channel queries bounded' do
      create_visible_cards_with_inbox_avatars(50)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies(limit: 50) }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:channel_widgets]).to be <= 1
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

      sql_queries = collect_sql_queries { query.call }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts.slice(:messages, :notes, :labels_tags_taggings)).to eq(messages: 0, notes: 0, labels_tags_taggings: 0)
    end
  end

  def query(limit: nil, cursor: nil)
    described_class.new(
      account: account,
      user: agent,
      kanban_board: kanban_board,
      kanban_stage: kanban_stage,
      limit: limit,
      cursor: cursor
    )
  end

  def create_visible_cards(count)
    Array.new(count) do |index|
      create_visible_card(position: index + 1, created_at: (count - index).minutes.ago, subject: "Card #{index}")
    end
  end

  def create_visible_cards_with_contact_avatars(count)
    Array.new(count) do |index|
      contact = create(:contact, :with_avatar, account: account)
      create_visible_card(contact: contact, position: index + 1, created_at: (count - index).minutes.ago, subject: "Card #{index}")
    end
  end

  def create_visible_cards_with_inbox_avatars(count)
    Array.new(count) do |index|
      visible_inbox = create(:inbox, account: account)
      visible_inbox.avatar.attach(avatar_fixture)
      create(:inbox_member, user: agent, inbox: visible_inbox)
      create_visible_card(inbox: visible_inbox, position: index + 1, created_at: (count - index).minutes.ago, subject: "Card #{index}")
    end
  end

  def load_compact_payload_dependencies(limit: nil)
    query(limit: limit).call.cards.each do |card|
      card.contact.avatar_url
      card.inbox.avatar_url
      card.inbox.channel.try(:provider)
      card.conversation&.display_id
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

  def avatar_fixture
    fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
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

  def visible_stage_cards_query_counts(sql_queries)
    {
      kanban_cards: table_query_count(sql_queries, 'kanban_cards'),
      inbox_members: table_query_count(sql_queries, 'inbox_members'),
      team_members: table_query_count(sql_queries, 'team_members'),
      active_storage_attachments: table_query_count(sql_queries, 'active_storage_attachments'),
      active_storage_blobs: table_query_count(sql_queries, 'active_storage_blobs'),
      channel_widgets: table_query_count(sql_queries, 'channel_web_widgets'),
      messages: table_query_count(sql_queries, 'messages'),
      notes: table_query_count(sql_queries, 'notes'),
      labels_tags_taggings: labels_tags_taggings_query_count(sql_queries)
    }
  end

  def table_query_count(sql_queries, table_name)
    sql_queries.count { |sql| sql.match?(/FROM "#{table_name}"|JOIN "#{table_name}"/) }
  end

  def labels_tags_taggings_query_count(sql_queries)
    sql_queries.count do |sql|
      sql.match?(/FROM "labels"|JOIN "labels"|FROM "tags"|JOIN "tags"|FROM "taggings"|JOIN "taggings"/)
    end
  end
end
