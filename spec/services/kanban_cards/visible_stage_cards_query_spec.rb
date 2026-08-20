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

    it 'sums discounted totals by card' do
      percentage_card = create_visible_card(position: 1)
      create_card_product(percentage_card, unit_price: 100, quantity: 2)
      percentage_card.update!(discount_percent: 10)

      amount_card = create_visible_card(position: 2)
      create_card_product(amount_card, unit_price: 300, quantity: 1)
      amount_card.update!(discount_cents: 5000)

      result = query.call

      expect(result.total_value).to eq('430.0')
    end

    it 'uses a default limit of 20' do
      cards = create_visible_cards(21)

      result = query.call

      expect(result.cards).to eq(cards.first(20))
      expect(result.has_more).to be(true)
    end

    it 'uses the given limit as-is' do
      cards = create_visible_cards(51)

      result = query(limit: 30).call

      expect(result.cards).to eq(cards.first(30))
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

    it 'restores payload cards to the id query order' do
      third_card = create_visible_card(position: 3)
      second_card = create_visible_card(position: 2)
      first_card = create_visible_card(position: 1)

      result = query.call

      expect(result.cards).to eq([first_card, second_card, third_card])
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

    it 'preserves administrator visibility' do
      administrator = create(:user, account: account, role: :administrator)
      administrator_account_user = administrator.account_users.find_by!(account: account)
      visible_card = create_visible_card(position: 1)
      unauthorized_inbox = create(:inbox, account: account)
      unauthorized_card = create_visible_card(position: 2, inbox: unauthorized_inbox)

      result = query(user: administrator, account_user: administrator_account_user).call

      expect(result.cards).to eq([visible_card, unauthorized_card])
    end

    it 'filters cards by inbox ids when provided' do
      second_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: second_inbox)
      visible_card = create_visible_card(position: 1, inbox: inbox)
      filtered_card = create_visible_card(position: 2, inbox: second_inbox)

      result = query(filtered_inbox_ids: [second_inbox.id]).call

      expect(result.cards).to eq([filtered_card])
      expect(result.total_count).to eq(1)
      expect(result.cards).not_to include(visible_card)
    end

    it 'keeps cursor and has_more coherent for filtered cards' do
      second_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: second_inbox)
      create_visible_card(position: 1, inbox: inbox)
      filtered_cards = [
        create_visible_card(position: 2, inbox: second_inbox),
        create_visible_card(position: 3, inbox: second_inbox)
      ]

      result = query(limit: 1, filtered_inbox_ids: [second_inbox.id]).call

      expect(result.cards).to eq([filtered_cards.first])
      expect(result.total_count).to eq(2)
      expect(result.has_more).to be(true)
      expect(result.next_cursor).to eq({ after_id: filtered_cards.first.id })
    end

    it 'filters cards by assignee ids when provided' do
      second_agent = create(:user, account: account, role: :agent)
      create_conversation_card(position: 1, assignees: [agent])
      filtered_card = create_conversation_card(position: 2, assignees: [second_agent])

      result = query(filtered_assignee_ids: [second_agent.id]).call

      expect(result.cards).to eq([filtered_card])
      expect(result.total_count).to eq(1)
    end

    it 'matches cards that carry any of the filtered assignees' do
      second_agent = create(:user, account: account, role: :agent)
      create_conversation_card(position: 1, assignees: [agent])
      shared_card = create_conversation_card(position: 2, assignees: [agent, second_agent])

      result = query(filtered_assignee_ids: [second_agent.id]).call

      expect(result.cards).to eq([shared_card])
      expect(result.total_count).to eq(1)
    end

    it 'ignores the conversation assignee when filtering by assignee ids' do
      second_agent = create(:user, account: account, role: :agent)
      create_conversation_card(position: 1, assignee: second_agent)

      result = query(filtered_assignee_ids: [second_agent.id]).call

      expect(result.cards).to be_empty
      expect(result.total_count).to eq(0)
    end

    it 'keeps cursor and has_more coherent for assignee filtered cards' do
      second_agent = create(:user, account: account, role: :agent)
      create_conversation_card(position: 1, assignees: [agent])
      filtered_cards = [
        create_conversation_card(position: 2, assignees: [second_agent]),
        create_conversation_card(position: 3, assignees: [second_agent])
      ]

      result = query(limit: 1, filtered_assignee_ids: [second_agent.id]).call

      expect(result.cards).to eq([filtered_cards.first])
      expect(result.total_count).to eq(2)
      expect(result.has_more).to be(true)
      expect(result.next_cursor).to eq({ after_id: filtered_cards.first.id })
    end

    it 'combines inbox and assignee filters' do
      second_agent = create(:user, account: account, role: :agent)
      second_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: second_inbox)
      create_conversation_card(position: 1, inbox: inbox, assignees: [second_agent])
      filtered_card = create_conversation_card(position: 2, inbox: second_inbox, assignees: [second_agent])
      create_conversation_card(position: 3, inbox: second_inbox, assignees: [agent])

      result = query(filtered_inbox_ids: [second_inbox.id], filtered_assignee_ids: [second_agent.id]).call

      expect(result.cards).to eq([filtered_card])
      expect(result.total_count).to eq(1)
    end

    it 'combines filter categories with all or any matching' do
      create(:label, account: account, title: 'vip')
      high_priority_card = create_visible_card(position: 1, priority: :high)
      labeled_card = create_visible_card(position: 2)
      matching_card = create_visible_card(position: 3, priority: :high)
      labeled_card.add_labels(['vip'])
      matching_card.add_labels(['vip'])

      all_match_result = query(filtered_priorities: ['high'], filtered_labels: ['vip']).call
      any_match_result = query(filtered_priorities: ['high'], filtered_labels: ['vip'], match_mode: 'any').call

      expect(all_match_result.cards).to eq([matching_card])
      expect(any_match_result.cards).to eq([high_priority_card, labeled_card, matching_card])
    end

    it 'filters cards by status relative to the board terminal stages' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
      kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)
      open_card = create_visible_card(position: 1)
      won_card = create_visible_card(kanban_stage: won_stage, position: 1)
      lost_card = create_visible_card(kanban_stage: lost_stage, position: 1)

      expect(query(filtered_card_statuses: ['open']).call.cards).to eq([open_card])
      expect(query(kanban_stage: won_stage, filtered_card_statuses: ['won']).call.cards).to eq([won_card])
      expect(query(kanban_stage: lost_stage, filtered_card_statuses: ['lost']).call.cards).to eq([lost_card])
    end

    it 'applies the default period only to terminal stages' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
      kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)

      recent_won_card = create_visible_card(kanban_stage: won_stage)
      old_won_card = create_visible_card(kanban_stage: won_stage)
      old_won_card.update_column(:stage_entered_at, 31.days.ago) # rubocop:disable Rails/SkipsModelValidations
      old_regular_card = create_visible_card
      old_regular_card.update_column(:stage_entered_at, 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(query(kanban_stage: won_stage).call.cards).to eq([recent_won_card])
      expect(query.call.cards).to include(old_regular_card)
    end

    it 'does not filter terminal cards when the period is all time' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
      kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)

      recent_card = create_visible_card(kanban_stage: won_stage)
      old_card = create_visible_card(kanban_stage: won_stage)
      old_card.update_column(:stage_entered_at, 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      result = query(kanban_stage: won_stage, terminal_period: 'all').call

      expect(result.cards).to contain_exactly(recent_card, old_card)
      expect(result.total_count).to eq(2)
    end

    it 'keeps the terminal period as an AND condition with any user filters' do
      create(:label, account: account, title: 'vip')
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2)
      lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3)
      kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)

      recent_card = create_visible_card(kanban_stage: won_stage, priority: :high)
      old_card = create_visible_card(kanban_stage: won_stage)
      old_card.add_labels(['vip'])
      old_card.update_column(:stage_entered_at, 31.days.ago) # rubocop:disable Rails/SkipsModelValidations

      result = query(
        kanban_stage: won_stage,
        terminal_period: '30d',
        filtered_priorities: ['high'],
        filtered_labels: ['vip'],
        match_mode: 'any'
      ).call

      expect(result.cards).to eq([recent_card])
      expect(result.total_count).to eq(1)
    end

    it 'filters card priorities including cards without a priority' do
      unprioritized_card = create_visible_card(position: 1)
      high_priority_card = create_visible_card(position: 2, priority: :high)

      expect(query(filtered_priorities: ['none']).call.cards).to eq([unprioritized_card])
      expect(query(filtered_priorities: ['high']).call.cards).to eq([high_priority_card])
    end

    it 'filters card due date buckets' do
      no_due_date_card = create_visible_card(position: 1)
      overdue_card = create_visible_card(position: 2, due_at: 1.hour.ago)
      day_card = create_visible_card(position: 3, due_at: 12.hours.from_now)
      week_card = create_visible_card(position: 4, due_at: 3.days.from_now)
      month_card = create_visible_card(position: 5, due_at: 2.weeks.from_now)

      expect(query(filtered_due_dates: ['none']).call.cards).to eq([no_due_date_card])
      expect(query(filtered_due_dates: ['overdue']).call.cards).to eq([overdue_card])
      expect(query(filtered_due_dates: ['day']).call.cards).to eq([day_card])
      expect(query(filtered_due_dates: ['week']).call.cards).to eq([day_card, week_card])
      expect(query(filtered_due_dates: ['month']).call.cards).to eq([day_card, week_card, month_card])
    end

    it 'filters cards by label and cards without labels' do
      create(:label, account: account, title: 'vip')
      unlabeled_card = create_visible_card(position: 1)
      labeled_card = create_visible_card(position: 2)
      labeled_card.add_labels(['vip'])

      expect(query(filtered_labels: ['vip']).call.cards).to eq([labeled_card])
      expect(query(filtered_labels: ['none']).call.cards).to eq([unlabeled_card])
    end

    it 'always combines search with category filters' do
      create(:label, account: account, title: 'vip')
      high_priority_card = create_visible_card(position: 1, priority: :high, subject: 'Needle in a haystack')
      labeled_card = create_visible_card(position: 2, subject: 'Needle by label')
      create_visible_card(position: 3, priority: :high, subject: 'Not a match')
      labeled_card.add_labels(['vip'])

      result = query(
        filtered_priorities: ['high'],
        filtered_labels: ['vip'],
        match_mode: 'any',
        search_query: 'needle'
      ).call

      expect(result.cards).to eq([high_priority_card, labeled_card])
    end

    it 'keeps manual cards when they carry the filtered assignee' do
      manual_card = create_visible_card(position: 1, assignees: [agent])
      create_visible_card(position: 2)

      result = query(filtered_assignee_ids: [agent.id]).call

      expect(result.cards).to eq([manual_card])
      expect(result.total_count).to eq(1)
    end

    it 'keeps historical cards visible without an explicit inbox filter' do
      historical_inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: historical_inbox)
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)
      visible_card = create_visible_card(position: 1, inbox: inbox)
      historical_card = create_visible_card(position: 2, inbox: historical_inbox)

      result = query.call

      expect(result.cards).to eq([visible_card, historical_card])
      expect(result.total_count).to eq(2)
    end

    it 'preserves agent bot visibility for conversation cards' do
      agent_bot = create(:agent_bot, account: account)
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      conversation_card = create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        position: 1
      )
      create_visible_card(position: 2)

      result = query(user: agent_bot).call

      expect(result.cards).to eq([conversation_card])
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

    it 'raises refresh-required error when cursor anchor is invisible' do
      unauthorized_inbox = create(:inbox, account: account)
      card = create_visible_card(position: 1, inbox: unauthorized_inbox)

      expect { query(cursor: { after_id: card.id }).call }.to raise_error(described_class::RefreshRequiredError)
    end

    it 'omits total_count on cursor-paginated pages to avoid recounting the whole stage' do
      cards = create_visible_cards(3)

      result = query(limit: 1, cursor: { after_id: cards.first.id }).call

      expect(result.cards).to eq([cards.second])
      expect(result.total_count).to be_nil
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

    it 'keeps compact payload assignee avatar queries bounded at the max page size' do
      create_visible_cards_with_assignee_avatars(50)

      sql_queries = collect_sql_queries { load_compact_payload_dependencies(limit: 50) }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:conversations]).to be <= 3
      expect(query_counts[:users]).to be <= 1
      expect(query_counts[:active_storage_attachments]).to be <= 3
      expect(query_counts[:active_storage_blobs]).to be <= 3
    end

    it 'preloads card labels at the default page size' do
      cards = create_visible_cards(20)
      cards.each { |card| card.add_labels(['enterprise']) }

      sql_queries = collect_sql_queries { query.call.cards.each { |card| card.labels.map(&:name) } }
      query_counts = visible_stage_cards_query_counts(sql_queries)

      expect(query_counts[:labels_tags_taggings]).to be <= 3
    end

    it 'explains the minimal ordered id query' do
      create_visible_cards(30)

      plan = explain_analyze_id_query

      expect(plan).to include('kanban_cards')
      expect(active_ordering_index_used?(plan) || plan.include?('Sort Key: kanban_cards."position"')).to be(true)
    end
  end

  def query(**options)
    described_class.new(
      account: account,
      kanban_board: kanban_board,
      kanban_stage: options.fetch(:kanban_stage, kanban_stage),
      visible_cards: visible_cards_scope(**options),
      limit: options[:limit],
      cursor: options[:cursor],
      terminal_period: options[:terminal_period]
    )
  end

  def visible_cards_scope(**options)
    KanbanCards::VisibleCardsScope.new(
      account: account,
      user: options.fetch(:user, agent),
      kanban_board: kanban_board,
      account_user: options[:account_user],
      filtered_inbox_ids: options[:filtered_inbox_ids],
      filtered_assignee_ids: options[:filtered_assignee_ids],
      filtered_card_statuses: options[:filtered_card_statuses],
      filtered_priorities: options[:filtered_priorities],
      filtered_due_dates: options[:filtered_due_dates],
      filtered_labels: options[:filtered_labels],
      match_mode: options[:match_mode],
      search_query: options[:search_query]
    ).call
  end

  def explain_analyze_id_query
    relation = query.send(:visible_cards).ordered.limit(described_class::DEFAULT_LIMIT + 1).select(:id)
    rows = ActiveRecord::Base.connection.execute("EXPLAIN ANALYZE #{relation.to_sql}")

    rows.map { |row| row['QUERY PLAN'] }.join("\n")
  end

  def active_ordering_index_used?(plan)
    plan.include?('index_active_kanban_cards_on_board_stage_order')
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

  def create_visible_cards_with_assignee_avatars(count)
    Array.new(count) do |index|
      assignee = create(:user, :with_avatar, account: account, role: :agent)
      create_conversation_card(assignee: assignee, position: index + 1, created_at: (count - index).minutes.ago)
    end
  end

  def load_compact_payload_dependencies(limit: nil)
    query(limit: limit).call.cards.each do |card|
      card.contact.avatar_url
      card.inbox.avatar_url
      card.inbox.channel.try(:provider)
      card.conversation&.display_id
      card.conversation&.priority
      card.conversation&.assignee&.avatar_url
    end
  end

  def create_visible_card(attributes = {})
    card_assignees = attributes.delete(:assignees)
    card = create(
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
    card.update_assignees!(card_assignees.map(&:id)) if card_assignees.present?
    card
  end

  def create_conversation_card(attributes = {})
    assignee = attributes.delete(:assignee)
    card_inbox = attributes[:inbox] || inbox
    contact = attributes[:contact] || create(:contact, account: account)
    conversation = create(:conversation, account: account, inbox: card_inbox, contact: contact, assignee: assignee)

    create_visible_card(attributes.merge(conversation: conversation, contact: contact, inbox: card_inbox, origin: 'conversation', subject: nil))
  end

  def create_card_product(card, attributes = {})
    KanbanCardProduct.create!(
      {
        account: account,
        kanban_card: card,
        sku: SecureRandom.hex(4),
        name: 'Product',
        unit_price: 10,
        quantity: 1
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
      conversations: table_query_count(sql_queries, 'conversations'),
      users: table_query_count(sql_queries, 'users'),
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
