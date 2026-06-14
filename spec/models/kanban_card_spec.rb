require 'rails_helper'

RSpec.describe KanbanCard do
  describe 'labels' do
    it 'can receive labels through Labelable' do
      card = create(:kanban_card)

      card.update_labels(%w[hot enterprise])

      expect(card.reload.label_list).to match_array(%w[hot enterprise])
    end
  end

  describe 'validations' do
    it 'allows a valid manual card' do
      card = build(:kanban_card)

      expect(card).to be_valid
    end

    it 'allows a valid conversation card' do
      card = build(:kanban_card, :conversation_origin)

      expect(card).to be_valid
    end

    it 'allows a card without starts_at and due_at' do
      card = build(:kanban_card, starts_at: nil, due_at: nil)

      expect(card).to be_valid
    end

    it 'allows a card with only starts_at' do
      card = build(:kanban_card, starts_at: 1.day.from_now, due_at: nil)

      expect(card).to be_valid
    end

    it 'allows a card with only due_at' do
      card = build(:kanban_card, starts_at: nil, due_at: 1.day.from_now)

      expect(card).to be_valid
    end

    it 'allows a card with equal starts_at and due_at' do
      scheduled_at = 1.day.from_now
      card = build(:kanban_card, starts_at: scheduled_at, due_at: scheduled_at)

      expect(card).to be_valid
    end

    it 'allows a card with due_at after starts_at' do
      starts_at = 1.day.from_now
      card = build(:kanban_card, starts_at: starts_at, due_at: starts_at + 1.hour)

      expect(card).to be_valid
    end

    it 'rejects a card with due_at before starts_at' do
      starts_at = 1.day.from_now
      card = build(:kanban_card, starts_at: starts_at, due_at: starts_at - 1.hour)

      expect(card).not_to be_valid
      expect(card.errors[:due_at]).to include('must be greater than or equal to starts at')
    end

    it 'requires a subject for manual cards' do
      card = build(:kanban_card, subject: ' ')

      expect(card).not_to be_valid
      expect(card.errors[:subject]).to be_present
      expect(card.errors[:normalized_subject]).to be_present
    end

    it 'requires a conversation for conversation cards' do
      card = build(:kanban_card, origin: 'conversation', conversation: nil, subject: nil)

      expect(card).not_to be_valid
      expect(card.errors[:conversation]).to be_present
    end

    it 'trims manual subject' do
      card = build(:kanban_card, subject: '  Cotação Notebook  ')

      card.valid?

      expect(card.subject).to eq('Cotação Notebook')
    end

    it 'collapses internal subject spaces' do
      card = build(:kanban_card, subject: 'Cotação   Notebook')

      card.valid?

      expect(card.subject).to eq('Cotação Notebook')
    end

    it 'stores lowercase normalized subject' do
      card = build(:kanban_card, subject: '  Cotação   Notebook  ')

      card.valid?

      expect(card.normalized_subject).to eq('cotação notebook')
    end

    it 'rejects duplicate active manual cards' do
      existing_card = create(:kanban_card, subject: 'Cotação Notebook')
      card = build(
        :kanban_card,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        contact: existing_card.contact,
        inbox: existing_card.inbox,
        subject: '  cotação   notebook  '
      )

      expect(card).not_to be_valid
      expect(card.errors[:normalized_subject]).to be_present
    end

    it 'allows manual cards for the same contact and inbox with different subjects' do
      existing_card = create(:kanban_card, subject: 'Cotação Notebook')
      card = build(
        :kanban_card,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        contact: existing_card.contact,
        inbox: existing_card.inbox,
        subject: 'Cotação Monitor'
      )

      expect(card).to be_valid
    end

    it 'allows active manual card recreation when existing card is inactive' do
      existing_card = create(:kanban_card, active: false, subject: 'Cotação Notebook')
      card = build(
        :kanban_card,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        contact: existing_card.contact,
        inbox: existing_card.inbox,
        subject: 'Cotação Notebook'
      )

      expect(card).to be_valid
    end

    it 'rejects duplicate active conversation cards with the same subject' do
      existing_card = create(:kanban_card, :conversation_origin, subject: 'Enterprise renewal')
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        conversation: existing_card.conversation,
        subject: '  enterprise   renewal  '
      )

      expect(card).not_to be_valid
      expect(card.errors[:conversation_id]).to be_present
    end

    it 'allows conversation cards for the same conversation with different subjects' do
      existing_card = create(:kanban_card, :conversation_origin, subject: 'Enterprise renewal')
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        conversation: existing_card.conversation,
        subject: 'Expansion project'
      )

      expect(card).to be_valid
    end

    it 'rejects conversation card recreation with the same subject when existing card is inactive' do
      existing_card = create(:kanban_card, :conversation_origin, active: false, subject: 'Enterprise renewal')
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        conversation: existing_card.conversation,
        subject: 'Enterprise renewal'
      )

      expect(card).not_to be_valid
      expect(card.errors[:conversation_id]).to be_present
    end

    it 'allows the same conversation card in different boards' do
      existing_card = create(:kanban_card, :conversation_origin)
      other_board = create(:kanban_board, account: existing_card.account)
      other_stage = create(:kanban_stage, account: existing_card.account, kanban_board: other_board)
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: other_board,
        kanban_stage: other_stage,
        conversation: existing_card.conversation
      )

      expect(card).to be_valid
    end

    it 'does not apply conversation uniqueness to manual cards' do
      conversation = create(:conversation)
      board = create(:kanban_board, account: conversation.account)
      stage = create(:kanban_stage, account: conversation.account, kanban_board: board)
      create(
        :kanban_card,
        account: conversation.account,
        kanban_board: board,
        kanban_stage: stage,
        contact: conversation.contact,
        inbox: conversation.inbox,
        conversation: conversation,
        subject: 'First opportunity'
      )
      card = build(
        :kanban_card,
        account: conversation.account,
        kanban_board: board,
        kanban_stage: stage,
        contact: conversation.contact,
        inbox: conversation.inbox,
        conversation: conversation,
        subject: 'Second opportunity'
      )

      expect(card).to be_valid
    end

    it 'blocks duplicate historical conversation cards with the same subject at the database index' do
      existing_card = create(:kanban_card, :conversation_origin, subject: 'Enterprise renewal')
      duplicate_attributes = existing_card.attributes.slice(
        'account_id',
        'kanban_board_id',
        'kanban_stage_id',
        'contact_id',
        'inbox_id',
        'conversation_id',
        'normalized_subject',
        'origin'
      ).merge(
        'subject' => 'Enterprise renewal',
        'position' => existing_card.position + 1,
        'active' => false,
        'stage_entered_at' => Time.current,
        'created_at' => Time.current,
        'updated_at' => Time.current
      )

      expect do
        described_class.insert_all!([duplicate_attributes]) # rubocop:disable Rails/SkipsModelValidations
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'rejects a stage from another board' do
      board = create(:kanban_board)
      other_board = create(:kanban_board, account: board.account)
      other_stage = create(:kanban_stage, account: board.account, kanban_board: other_board)
      card = build(:kanban_card, account: board.account, kanban_board: board, kanban_stage: other_stage)

      expect(card).not_to be_valid
      expect(card.errors[:kanban_stage]).to be_present
    end

    it 'rejects a board from another account' do
      card = build(:kanban_card)
      card.kanban_board = create(:kanban_board)

      expect(card).not_to be_valid
      expect(card.errors[:kanban_board]).to be_present
    end

    it 'rejects a stage from another account' do
      card = build(:kanban_card)
      card.kanban_stage = create(:kanban_stage)

      expect(card).not_to be_valid
      expect(card.errors[:kanban_stage]).to be_present
    end

    it 'rejects a contact from another account' do
      card = build(:kanban_card)
      card.contact = create(:contact)

      expect(card).not_to be_valid
      expect(card.errors[:contact]).to be_present
    end

    it 'rejects an inbox from another account' do
      card = build(:kanban_card)
      card.inbox = create(:inbox)

      expect(card).not_to be_valid
      expect(card.errors[:inbox]).to be_present
    end

    it 'rejects an optional conversation from another account' do
      card = build(:kanban_card)
      card.conversation = create(:conversation)

      expect(card).not_to be_valid
      expect(card.errors[:conversation]).to be_present
    end

    it 'rejects an optional conversation with another contact' do
      conversation = create(:conversation)
      card = build(
        :kanban_card,
        account: conversation.account,
        conversation: conversation,
        contact: create(:contact, account: conversation.account),
        inbox: conversation.inbox
      )

      expect(card).not_to be_valid
      expect(card.errors[:conversation]).to be_present
    end

    it 'rejects an optional conversation with another inbox' do
      conversation = create(:conversation)
      card = build(
        :kanban_card,
        account: conversation.account,
        conversation: conversation,
        contact: conversation.contact,
        inbox: create(:inbox, account: conversation.account)
      )

      expect(card).not_to be_valid
      expect(card.errors[:conversation]).to be_present
    end
  end

  describe '.active' do
    it 'returns only active cards' do
      active_card = create(:kanban_card, active: true)
      create(:kanban_card, active: false)

      expect(described_class.active).to contain_exactly(active_card)
    end
  end

  describe '.ordered' do
    it 'orders by position, creation time, and id' do
      newer_card = create(:kanban_card, position: 2, created_at: 1.day.ago)
      earlier_card = create(:kanban_card, position: 1, created_at: 2.days.ago)
      first_duplicate = create(:kanban_card, position: 1, created_at: 1.day.ago)
      second_duplicate = create(:kanban_card, position: 1, created_at: 1.day.ago)

      expect(described_class.ordered).to eq([earlier_card, first_duplicate, second_duplicate, newer_card])
    end
  end

  describe '.normalize_positions_for_stage!' do
    it 'assigns sequential positions to active cards ordered by position, creation time, and id' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      later_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)
      first_duplicate = create(
        :kanban_card,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        position: 1,
        created_at: 2.days.ago
      )
      second_duplicate = create(
        :kanban_card,
        account: board.account,
        kanban_board: board,
        kanban_stage: stage,
        position: 1,
        created_at: 1.day.ago
      )

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(first_duplicate.reload.position).to eq(1)
      expect(second_duplicate.reload.position).to eq(2)
      expect(later_card.reload.position).to eq(3)
    end

    it 'excludes inactive cards' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      inactive_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1, active: false)
      active_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 10)

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(active_card.reload.position).to eq(1)
      expect(inactive_card.reload.position).to eq(1)
    end

    it 'updates updated_at only for active cards whose positions change' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      original_time = 2.days.ago
      unchanged_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1, updated_at: original_time)
      changed_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 10, updated_at: original_time)
      inactive_card = create(
        :kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2, active: false, updated_at: original_time
      )

      travel_to(Time.zone.parse('2026-01-01 12:00:00 UTC')) do
        described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)
      end

      expect(unchanged_card.reload.updated_at.to_i).to eq(original_time.to_i)
      expect(changed_card.reload.updated_at.to_i).to eq(Time.zone.parse('2026-01-01 12:00:00 UTC').to_i)
      expect(inactive_card.reload.updated_at.to_i).to eq(original_time.to_i)
    end

    it 'does not query taggings while normalizing positions' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 10)
      create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 20)

      sql_queries = collect_sql_queries do
        described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)
      end

      expect(labels_tags_taggings_query_count(sql_queries)).to eq(0)
    end

    it 'does not touch cards from other boards' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      other_board = create(:kanban_board, account: board.account)
      other_stage = create(:kanban_stage, account: board.account, kanban_board: other_board)
      card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 10)
      other_board_card = create(:kanban_card, account: board.account, kanban_board: other_board, kanban_stage: other_stage, position: 10)

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(card.reload.position).to eq(1)
      expect(other_board_card.reload.position).to eq(10)
    end

    it 'does not touch cards from other stages' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      other_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 10)
      other_stage_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: other_stage, position: 10)

      described_class.normalize_positions_for_stage!(kanban_board: board, kanban_stage: stage)

      expect(card.reload.position).to eq(1)
      expect(other_stage_card.reload.position).to eq(10)
    end
  end

  describe '#reorder_to_position!' do
    it 'reorders cards within the same stage' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)
      third_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 3)

      third_card.reorder_to_position!(kanban_stage: stage, position: 1)

      expect(stage_positions(stage)).to eq([third_card.id, first_card.id, second_card.id])
    end

    it 'clamps same-stage positions below the minimum' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)

      second_card.reorder_to_position!(kanban_stage: stage, position: 0)

      expect(stage_positions(stage)).to eq([second_card.id, first_card.id])
    end

    it 'clamps same-stage positions above the maximum' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)

      first_card.reorder_to_position!(kanban_stage: stage, position: 10)

      expect(stage_positions(stage)).to eq([second_card.id, first_card.id])
    end

    it 'reorders cards across stages' do
      board = create(:kanban_board)
      source_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      target_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      moved_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: source_stage, position: 1)
      target_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: target_stage, position: 1)

      moved_card.reorder_to_position!(kanban_stage: target_stage, position: 1)

      expect(stage_positions(source_stage)).to eq([])
      expect(stage_positions(target_stage)).to eq([moved_card.id, target_card.id])
      expect(moved_card.reload.kanban_stage).to eq(target_stage)
    end

    it 'normalizes the source stage after a cross-stage move' do
      board = create(:kanban_board)
      source_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      target_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      moved_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: source_stage, position: 1)
      remaining_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: source_stage, position: 10)

      moved_card.reorder_to_position!(kanban_stage: target_stage, position: 1)

      expect(remaining_card.reload.position).to eq(1)
    end

    it 'normalizes the destination stage after a cross-stage move' do
      board = create(:kanban_board)
      source_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      target_stage = create(:kanban_stage, account: board.account, kanban_board: board)
      moved_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: source_stage, position: 1)
      first_target_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: target_stage, position: 10)
      second_target_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: target_stage, position: 20)

      moved_card.reorder_to_position!(kanban_stage: target_stage, position: 2)

      expect(first_target_card.reload.position).to eq(1)
      expect(moved_card.reload.position).to eq(2)
      expect(second_target_card.reload.position).to eq(3)
    end

    it 'rejects reordering inactive cards' do
      card = create(:kanban_card, active: false, position: 10)

      expect do
        card.reorder_to_position!(kanban_stage: card.kanban_stage, position: 1)
      end.to raise_error(ActiveRecord::RecordNotSaved, 'Inactive kanban cards cannot be reordered')
      expect(card.reload.position).to eq(10)
    end

    it 'keeps soft-deleted card positions unchanged when active cards reorder' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      inactive_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1, active: false)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 3)

      second_card.reorder_to_position!(kanban_stage: stage, position: 1)

      expect(stage_positions(stage)).to eq([second_card.id, first_card.id])
      expect(inactive_card.reload.position).to eq(1)
    end

    it 'reorders manual cards and conversation cards identically' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      manual_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      conversation = create(:conversation, account: board.account)
      conversation_card = create(
        :kanban_card,
        :conversation_origin,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation,
        position: 2
      )

      conversation_card.reorder_to_position!(kanban_stage: stage, position: 1)
      expect(stage_positions(stage)).to eq([conversation_card.id, manual_card.id])

      manual_card.reorder_to_position!(kanban_stage: stage, position: 1)
      expect(stage_positions(stage)).to eq([manual_card.id, conversation_card.id])
    end

    it 'updates updated_at for mechanically reordered rows' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1, updated_at: 2.days.ago)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2, updated_at: 2.days.ago)

      travel_to(Time.zone.parse('2026-01-01 12:00:00 UTC')) do
        second_card.reorder_to_position!(kanban_stage: stage, position: 1)
      end

      expect(first_card.reload.updated_at.to_i).to eq(Time.zone.parse('2026-01-01 12:00:00 UTC').to_i)
      expect(second_card.reload.updated_at.to_i).to eq(Time.zone.parse('2026-01-01 12:00:00 UTC').to_i)
    end

    it 'does not query taggings while reordering positions' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 2)
      first_card.update_labels(%w[hot])
      second_card.update_labels(%w[warm])

      sql_queries = collect_sql_queries do
        second_card.reorder_to_position!(kanban_stage: stage, position: 1)
      end

      expect(labels_tags_taggings_query_count(sql_queries)).to eq(0)
    end

    it 'deactivates and normalizes remaining active cards' do
      board = create(:kanban_board)
      stage = create(:kanban_stage, account: board.account, kanban_board: board)
      first_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 1)
      second_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 5)
      inactive_card = create(:kanban_card, account: board.account, kanban_board: board, kanban_stage: stage, position: 20, active: false)

      first_card.deactivate_and_normalize!

      expect(first_card.reload).not_to be_active
      expect(second_card.reload.position).to eq(1)
      expect(inactive_card.reload.position).to eq(20)
    end

    def stage_positions(stage)
      described_class.where(kanban_stage: stage).active.ordered.pluck(:id)
    end
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
end
