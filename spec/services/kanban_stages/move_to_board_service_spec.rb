require 'rails_helper'

RSpec.describe KanbanStages::MoveToBoardService do
  let(:account) { create(:account) }
  let(:source_board) { create(:kanban_board, account: account, name: 'Sales') }
  let(:target_board) { create(:kanban_board, account: account, name: 'Support') }
  let(:source_stage) do
    create(:kanban_stage, account: account, kanban_board: source_board, name: 'Negotiation', position: 1)
  end
  let!(:source_sibling_stage) do
    create(:kanban_stage, account: account, kanban_board: source_board, name: 'Proposal', position: 2)
  end
  let(:target_stage) do
    create(:kanban_stage, account: account, kanban_board: target_board, name: 'Triage', position: 1)
  end
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: source_board,
      kanban_stage: source_stage,
      contact: contact,
      inbox: inbox,
      subject: 'Expansion opportunity',
      position: 3,
      stage_entered_at: 5.days.ago
    )
  end
  let(:service) do
    described_class.new(stage: source_stage, target_board: target_board, position: 1, user: nil)
  end

  def create_field(board, key:, **attributes)
    KanbanCustomField.create!(
      {
        account: account,
        kanban_board: board,
        key: key,
        field_type: :text,
        multiple: false,
        position: 1,
        active: true
      }.merge(attributes)
    )
  end

  def create_field_value(card, field, value)
    KanbanCardFieldValue.create!(account: account, kanban_card: card, kanban_custom_field: field, value: value)
  end

  describe '#perform!' do
    it 'moves the stage with cards, remaps fields, and repoints the timeline' do
      source_shared = create_field(source_board, key: 'shared')
      source_missing = create_field(source_board, key: 'missing')
      source_type_mismatch = create_field(source_board, key: 'type_mismatch')
      target_shared = create_field(target_board, key: 'shared')
      create_field(target_board, key: 'type_mismatch', field_type: :number)
      create_field_value(card, source_shared, ['kept'])
      create_field_value(card, source_missing, ['discarded'])
      create_field_value(card, source_type_mismatch, ['discarded'])
      old_event = create(:kanban_card_event, account: account, kanban_card: card, kanban_board: source_board)
      previous_stage_id = source_sibling_stage.id
      card.update!(previous_stage_id: previous_stage_id)
      stage_entered_at = card.stage_entered_at

      result = service.perform!

      expect(result).to have_attributes(success?: true, moved_count: 1, source_board_id: source_board.id)
      expect(source_stage.reload).to have_attributes(kanban_board_id: target_board.id, position: 1)
      expect(card.reload).to have_attributes(
        kanban_board_id: target_board.id,
        kanban_stage_id: source_stage.id,
        position: 3,
        previous_stage_id: nil,
        kanban_reason_id: nil,
        stage_entered_at: stage_entered_at
      )
      expect(card.kanban_card_field_values.pluck(:kanban_custom_field_id)).to eq([target_shared.id])
      expect(card.kanban_card_field_values.first.value).to eq(['kept'])
      expect(old_event.reload.kanban_board_id).to eq(target_board.id)

      event = KanbanCardEvent.find_by!(kanban_card_id: card.id, event_type: 'board_changed')
      expect(event.metadata).to include(
        'from_board_id' => source_board.id,
        'from_board_name' => 'Sales',
        'to_board_id' => target_board.id,
        'to_board_name' => 'Support',
        'from_stage_id' => source_stage.id,
        'from_stage_name' => 'Negotiation',
        'to_stage_id' => source_stage.id,
        'to_stage_name' => 'Negotiation',
        'reason_cleared' => false,
        'dropped_field_keys' => %w[missing type_mismatch],
        'moved_with_stage' => true
      )
    end

    it 'clears a card reason and keeps each card position and stage clock unchanged' do
      reason = KanbanReason.create!(account: account, kanban_board: source_board, title: 'Price', reason_type: :lost)
      card.update!(kanban_reason: reason, position: 7)
      stage_entered_at = card.stage_entered_at

      result = service.perform!

      expect(result).to be_success
      expect(card.reload).to have_attributes(
        position: 7,
        stage_entered_at: stage_entered_at,
        kanban_reason_id: nil,
        previous_stage_id: nil
      )
      expect(KanbanCardEvent.last.metadata).to include('reason_cleared' => true)
    end

    it 'moves all active cards without a card count limit' do
      cards = Array.new(3) do |index|
        create(
          :kanban_card,
          account: account,
          kanban_board: source_board,
          kanban_stage: source_stage,
          contact: create(:contact, account: account),
          inbox: inbox,
          subject: "Opportunity #{index}",
          position: index + 1
        )
      end

      result = service.perform!

      expect(result.moved_count).to eq(3)
      expect(KanbanCard.where(id: cards.map(&:id)).pluck(:kanban_board_id, :kanban_stage_id)).to all(
        eq([target_board.id, source_stage.id])
      )
      expect(KanbanCardEvent.where(kanban_card_id: cards.map(&:id), event_type: 'board_changed').count).to eq(3)
    end

    it 'rejects the whole stage when one card already exists on the destination board' do
      second_card = create(
        :kanban_card,
        account: account,
        kanban_board: source_board,
        kanban_stage: source_stage,
        contact: create(:contact, account: account),
        inbox: inbox,
        subject: 'Second opportunity',
        position: 4
      )
      create(
        :kanban_card,
        account: account,
        kanban_board: target_board,
        kanban_stage: target_stage,
        contact: card.contact,
        inbox: card.inbox,
        subject: card.subject
      )
      old_event = create(:kanban_card_event, account: account, kanban_card: card, kanban_board: source_board)

      result = service.perform!

      expect(result).not_to be_success
      expect(result.error).to eq('stage_cards_blocked')
      expect(result.blocked).to eq('card_already_in_target_board' => 1)
      expect(source_stage.reload.kanban_board_id).to eq(source_board.id)
      expect(KanbanCard.where(id: [card.id, second_card.id]).pluck(:kanban_board_id)).to all(eq(source_board.id))
      expect(old_event.reload.kanban_board_id).to eq(source_board.id)
      expect(KanbanCardEvent.where(kanban_card_id: [card.id, second_card.id], event_type: 'board_changed')).to be_empty
    end

    it 'rejects the whole stage when an inbox is outside the destination scope' do
      card
      target_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: target_board, inbox: create(:inbox, account: account))

      result = service.perform!

      expect(result).not_to be_success
      expect(result.error).to eq('stage_cards_blocked')
      expect(result.blocked).to eq('inbox_not_allowed' => 1)
      expect(source_stage.reload.kanban_board_id).to eq(source_board.id)
      expect(card.reload.kanban_board_id).to eq(source_board.id)
    end

    it 'rejects a duplicate stage name on the destination' do
      create(:kanban_stage, account: account, kanban_board: target_board, name: source_stage.name)

      result = service.perform!

      expect(result).to have_attributes(success?: false, error: 'stage_name_taken')
      expect(source_stage.reload.kanban_board_id).to eq(source_board.id)
    end

    it 'rejects the last regular stage on the source board' do
      last_source_board = create(:kanban_board, account: account, name: 'Solo source')
      last_source_stage = create(:kanban_stage, account: account, kanban_board: last_source_board, name: 'Only list')
      last_target_board = create(:kanban_board, account: account, name: 'Other target')
      create(:kanban_stage, account: account, kanban_board: last_target_board, name: 'Target list')

      result = described_class.new(
        stage: last_source_stage,
        target_board: last_target_board,
        position: 1,
        user: nil
      ).perform!

      expect(result).to have_attributes(success?: false, error: 'last_stage_cannot_move_board')
      expect(last_source_stage.reload.kanban_board_id).to eq(last_source_board.id)
    end

    it 'continues to reject terminal stages' do
      won_stage = create(:kanban_stage, account: account, kanban_board: source_board, name: 'Won', position: 3)
      source_board.update!(won_stage_id: won_stage.id)

      result = described_class.new(stage: won_stage, target_board: target_board, position: 1, user: nil).perform!

      expect(result).to have_attributes(success?: false, error: 'special_stage_cannot_move_board')
      expect(won_stage.reload.kanban_board_id).to eq(source_board.id)
    end
  end
end
