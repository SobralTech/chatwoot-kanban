require 'rails_helper'

RSpec.describe KanbanCards::AutoCreateFromConversationService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Comercial') }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:board) { create_eligible_board }
  let(:service) { described_class.new(conversation) }

  describe '#perform!' do
    it 'creates an automatic card for an eligible board' do
      board

      expect { service.perform! }.to change(KanbanCard, :count).by(1)

      expect(created_card).to have_attributes(
        origin: 'conversation',
        conversation_id: conversation.id,
        contact_id: contact.id,
        inbox_id: inbox.id,
        kanban_board_id: board.id,
        kanban_stage_id: first_stage.id,
        position: 1,
        active: true
      )
    end

    it 'sets stage_entered_at' do
      board

      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        service.perform!
      end

      expect(created_card.stage_entered_at).to eq(Time.zone.parse('2026-06-09 12:00:00 UTC'))
    end

    it 'emits kanban.card.created with a compact payload' do
      board
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      service.perform!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        {
          account_id: account.id,
          board_id: board.id,
          stage_id: first_stage.id,
          card_id: created_card.id,
          conversation_id: conversation.id
        }
      )
    end

    it 'generates the default subject from contact and inbox names' do
      board

      service.perform!

      expect(created_card.subject).to eq('Maria da Silva - WhatsApp Comercial')
    end

    it 'uses fallback names when contact and inbox names are blank' do
      contact.update!(name: '')
      inbox.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations
      board

      service.perform!

      expect(created_card.subject).to eq("Contact ##{contact.id} - Inbox ##{inbox.id}")
    end

    it 'normalizes the generated subject' do
      board

      service.perform!

      expect(created_card.normalized_subject).to eq('maria da silva - whatsapp comercial')
    end

    it 'inserts the card at the top of the first active stage' do
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: first_stage, position: 1)

      service.perform!

      expect(created_card.position).to eq(1)
    end

    it 'shifts existing active cards down in the target stage' do
      first_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: first_stage, position: 1)
      second_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: first_stage, position: 2)

      service.perform!

      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'updates updated_at for mechanically shifted cards' do
      shifted_card = create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: first_stage,
        position: 1,
        updated_at: 2.days.ago
      )

      travel_to(Time.zone.parse('2026-01-01 12:00:00 UTC')) do
        service.perform!
      end

      expect(shifted_card.reload.updated_at.to_i).to eq(Time.zone.parse('2026-01-01 12:00:00 UTC').to_i)
    end

    it 'does not query labels tags or taggings per shifted card' do
      baseline_query_count = labels_tags_taggings_query_count_for_automatic_insert(card_count: 0)
      shifted_query_count = labels_tags_taggings_query_count_for_automatic_insert(card_count: 5)

      expect(shifted_query_count).to eq(baseline_query_count)
    end

    it 'leaves inactive cards untouched when inserting at the top' do
      inactive_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: first_stage, position: 1, active: false)

      service.perform!

      expect(created_card.position).to eq(1)
      expect(inactive_card.reload.position).to eq(1)
    end

    it 'leaves cards in other stages untouched when inserting at the top' do
      other_stage = create(:kanban_stage, account: account, kanban_board: board, position: 2)
      other_stage_card = create(:kanban_card, account: account, kanban_board: board, kanban_stage: other_stage, position: 1)

      service.perform!

      expect(created_card.position).to eq(1)
      expect(other_stage_card.reload.position).to eq(1)
    end

    it 'creates cards for multiple eligible boards in the same account' do
      first_board = board
      second_board = create_eligible_board

      expect { service.perform! }.to change(KanbanCard, :count).by(2)

      expect(KanbanCard.conversation.where(conversation: conversation).pluck(:kanban_board_id)).to contain_exactly(first_board.id, second_board.id)
    end

    it 'does not create for an inactive board' do
      board.update!(active: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'creates card on selected_agents board without user interaction' do
      board.update!(visibility_mode: 'selected_agents')

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
      expect(created_card).to be_present
    end

    it 'creates on board when inbox is selected in selected_inboxes mode' do
      board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: board, inbox: inbox)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'ignores board in selected_inboxes mode when inbox is not selected' do
      board.update!(inbox_scope_mode: 'selected_inboxes')

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'creates only on eligible boards when multiple boards exist' do
      board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: board, inbox: inbox)
      second_board = create_eligible_board
      second_board.update!(inbox_scope_mode: 'selected_inboxes')

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
      expect(created_card.kanban_board_id).to eq(board.id)
    end

    it 'does not create when automation is disabled' do
      board.update!(auto_create_cards_from_conversations: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'creates when opportunity-card reads are disabled' do
      board.update!(use_opportunity_card_reads: false)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'creates the card in the first active stage ordered by position, created_at, and id' do
      timestamp = 3.days.ago.change(usec: 0)
      create(:kanban_stage, account: account, kanban_board: board, position: 2, created_at: timestamp - 1.day)
      destination_stage = create(:kanban_stage, account: account, kanban_board: board, position: 1, created_at: timestamp)
      create(:kanban_stage, account: account, kanban_board: board, position: 1, created_at: timestamp + 1.day)

      service.perform!

      expect(created_card.kanban_stage_id).to eq(destination_stage.id)
    end

    it 'uses the reordered first stage for future automatic cards' do
      next_stage = create(:kanban_stage, account: account, kanban_board: board, position: 2)
      first_stage.update!(position: 3)
      next_stage.update!(position: 1)

      service.perform!

      expect(created_card.kanban_stage_id).to eq(next_stage.id)
    end

    it 'ignores inactive first stages' do
      inactive_stage = create(:kanban_stage, account: account, kanban_board: board, position: 0, active: false)

      service.perform!

      expect(created_card.kanban_stage_id).to eq(first_stage.id)
      expect(created_card.kanban_stage_id).not_to eq(inactive_stage.id)
    end

    it 'does not create without an active stage' do
      first_stage.update!(active: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create when contact is missing' do
      board
      allow(conversation).to receive(:contact).and_return(nil)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create when inbox is missing' do
      board
      allow(conversation).to receive(:inbox).and_return(nil)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not duplicate an active automatic card' do
      create_automatic_card(active: true)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not emit kanban.card.created for an automatic duplicate skip' do
      create_automatic_card(active: true)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      service.perform!

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'does not recreate an inactive historical automatic card' do
      inactive_card = create_automatic_card(active: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
      expect(inactive_card.reload).not_to be_active
    end

    it 'treats RecordNotUnique as a safe no-op' do
      board
      allow(KanbanCard).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect { service.perform! }.not_to raise_error
      expect(KanbanCard.count).to eq(0)
    end

    it 'does not emit kanban.card.created for a RecordNotUnique no-op' do
      board
      allow(KanbanCard).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      service.perform!

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'does not create a ConversationKanbanState' do
      board

      expect { service.perform! }.not_to change(ConversationKanbanState, :count)
    end

    it 'returns summary counts' do
      existing_board = board
      create_automatic_card(kanban_board: existing_board)
      invalid_board = create_eligible_board
      invalid_board.kanban_stages.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
      create_eligible_board

      expect(service.perform!).to eq(
        created: 1,
        skipped: {
          existing_card: 1,
          without_active_stage: 1
        }
      )
    end
  end

  def create_eligible_board
    kanban_board = create(
      :kanban_board,
      account: account,
      auto_create_cards_from_conversations: true,
      use_opportunity_card_reads: true
    )
    create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1)
    kanban_board
  end

  def create_automatic_card(kanban_board: board, active: true)
    stage = kanban_board.kanban_stages.active.ordered.first

    create(
      :kanban_card,
      :conversation_origin,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: stage,
      conversation: conversation,
      active: active
    )
  end

  def created_card
    KanbanCard.conversation.find_by!(conversation: conversation)
  end

  def first_stage
    board.kanban_stages.active.ordered.first
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

  def labels_tags_taggings_query_count(sql_queries)
    sql_queries.count do |sql|
      sql.match?(/FROM "labels"|JOIN "labels"|FROM "tags"|JOIN "tags"|FROM "taggings"|JOIN "taggings"/)
    end
  end

  def labels_tags_taggings_query_count_for_automatic_insert(card_count:)
    local_conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
    local_board = create_eligible_board
    local_stage = local_board.kanban_stages.active.ordered.first
    create_labeled_cards(local_board, local_stage, card_count)

    labels_tags_taggings_query_count(collect_sql_queries { described_class.new(local_conversation).perform! })
  ensure
    local_board&.update!(auto_create_cards_from_conversations: false)
  end

  def create_labeled_cards(kanban_board, stage, count)
    Array.new(count) do |index|
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: stage, position: index + 1).tap do |card|
        card.update_labels(["label-#{index}"])
      end
    end
  end
end
