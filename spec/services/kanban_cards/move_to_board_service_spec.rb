require 'rails_helper'

RSpec.describe KanbanCards::MoveToBoardService do
  let(:account) { create(:account) }
  let(:source_board) { create(:kanban_board, account: account, name: 'Sales') }
  let(:target_board) { create(:kanban_board, account: account, name: 'Support') }
  let(:source_stage) { create(:kanban_stage, account: account, kanban_board: source_board, name: 'Negotiation') }
  let(:target_stage) { create(:kanban_stage, account: account, kanban_board: target_board, name: 'Triage') }
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
      position: 1
    )
  end
  let(:service) do
    described_class.new(card: card, target_board: target_board, target_stage_id: target_stage.id, user: nil)
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
    it 'remaps matching fields and drops missing or incompatible fields' do
      source_shared = create_field(source_board, key: 'shared')
      source_missing = create_field(source_board, key: 'missing')
      source_type_mismatch = create_field(source_board, key: 'type_mismatch')
      source_multiple_mismatch = create_field(source_board, key: 'multiple_mismatch')
      target_shared = create_field(target_board, key: 'shared')
      create_field(target_board, key: 'type_mismatch', field_type: :number)
      create_field(target_board, key: 'multiple_mismatch', multiple: true)

      create_field_value(card, source_shared, ['kept'])
      create_field_value(card, source_missing, ['discarded'])
      create_field_value(card, source_type_mismatch, ['discarded'])
      create_field_value(card, source_multiple_mismatch, ['discarded'])

      result = service.perform!

      expect(result).to be_success
      expect(card.reload.kanban_card_field_values.pluck(:kanban_custom_field_id)).to eq([target_shared.id])
      expect(card.kanban_card_field_values.first.value).to eq(['kept'])

      event = KanbanCardEvent.find_by!(kanban_card_id: card.id, event_type: 'board_changed')
      expect(event.metadata).to include(
        'from_board_id' => source_board.id,
        'from_board_name' => 'Sales',
        'to_board_id' => target_board.id,
        'to_board_name' => 'Support',
        'from_stage_id' => source_stage.id,
        'from_stage_name' => 'Negotiation',
        'to_stage_id' => target_stage.id,
        'to_stage_name' => 'Triage',
        'reason_cleared' => false,
        'dropped_field_keys' => %w[missing multiple_mismatch type_mismatch]
      )
    end

    it 'reopens terminal cards and clears reason and previous stage' do
      lost_stage = create(:kanban_stage, account: account, kanban_board: source_board, name: 'Lost')
      previous_stage = create(:kanban_stage, account: account, kanban_board: source_board, name: 'Earlier')
      source_board.update!(lost_stage_id: lost_stage.id)
      reason = KanbanReason.create!(account: account, kanban_board: source_board, title: 'Price', reason_type: :lost)
      card.update!(kanban_stage: lost_stage, kanban_reason: reason, previous_stage: previous_stage)
      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) { service.perform! }

      expect(card.reload).to have_attributes(
        kanban_board_id: target_board.id,
        kanban_stage_id: target_stage.id,
        position: 1000,
        kanban_reason_id: nil,
        previous_stage_id: nil,
        stage_entered_at: Time.zone.parse('2026-06-09 12:00:00 UTC')
      )
      expect(KanbanCardEvent.last.metadata).to include('reason_cleared' => true)
    end

    it 'appends the card past the destination stage and leaves both stages in place' do
      moving_card = card
      moving_card.update!(position: 3000)
      source_tail = create(:kanban_card, account: account, kanban_board: source_board, kanban_stage: source_stage,
                                         contact: contact, inbox: inbox, subject: 'Source tail', position: 7000)
      target_first = create(:kanban_card, account: account, kanban_board: target_board, kanban_stage: target_stage,
                                          contact: contact, inbox: inbox, subject: 'Target first', position: 2000)

      service.perform!

      expect(KanbanCard.stage_active_cards(source_board, source_stage).pluck(:id)).to eq([source_tail.id])
      expect(KanbanCard.stage_active_cards(target_board, target_stage).pluck(:id)).to eq([target_first.id, moving_card.id])
      expect(moving_card.reload.position).to eq(3000)
      expect(source_tail.reload.position).to eq(7000)
      expect(target_first.reload.position).to eq(2000)
    end

    it 'returns a duplicate error without changing the source card' do
      create(:kanban_card, account: account, kanban_board: target_board, kanban_stage: target_stage,
                           contact: contact, inbox: inbox, subject: card.subject, position: 1)

      result = service.perform!

      expect(result).not_to be_success
      expect(result.error).to eq('card_already_in_target_board')
      expect(card.reload).to have_attributes(kanban_board_id: source_board.id, kanban_stage_id: source_stage.id)
      expect(KanbanCardEvent.where(kanban_card_id: card.id, event_type: 'board_changed')).to be_empty
    end

    it 'returns an error for a terminal target stage' do
      target_board.update!(won_stage_id: target_stage.id)

      result = service.perform!

      expect(result).not_to be_success
      expect(result.error).to eq('invalid_target_stage')
      expect(card.reload.kanban_board_id).to eq(source_board.id)
    end

    it 'returns an error when the target board rejects the card inbox' do
      target_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: target_board, inbox: create(:inbox, account: account))

      result = service.perform!

      expect(result).not_to be_success
      expect(result.error).to eq('inbox_not_allowed')
      expect(card.reload.kanban_board_id).to eq(source_board.id)
    end
  end
end
