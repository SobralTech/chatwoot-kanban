require 'rails_helper'

RSpec.describe KanbanCards::EvaluateContactRecurrenceService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account, name: 'Current inbox') }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:board) { create(:kanban_board, account: account, won_recurrence_enabled: true, won_recurrence_window_hours: 12) }
  let!(:regular_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 1) }
  let!(:won_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 2) }
  let!(:lost_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 3) }
  let(:service) { described_class.new(conversation: conversation, kanban_board: board) }

  before do
    board.update!(won_stage: won_stage, lost_stage: lost_stage)
  end

  describe '#perform!' do
    it 'does not create a card inside the won recurrence window' do
      terminal_card = create_terminal_card(won_stage, stage_entered_at: 1.hour.ago)

      expect { service.perform! }.not_to change(KanbanCard, :count)
      expect(terminal_card.reload).to have_attributes(kanban_stage_id: won_stage.id, active: true)
    end

    it 'creates a blank card outside the won recurrence window' do
      terminal_card = create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)

      recreated_card = KanbanCard.order(:id).last
      expect(recreated_card).to have_attributes(
        kanban_board_id: board.id,
        kanban_stage_id: regular_stage.id,
        contact_id: contact.id,
        inbox_id: inbox.id,
        recreated_from_card_id: terminal_card.id,
        description: nil,
        priority: nil,
        due_at: nil,
        starts_at: nil
      )
      expect(recreated_card.kanban_card_products).to be_empty
      expect(recreated_card.assignees).to be_empty
    end

    it 'uses the lost recurrence window independently from the won window' do
      board.update!(lost_recurrence_enabled: true, lost_recurrence_window_hours: 48)
      terminal_card = create_terminal_card(lost_stage, stage_entered_at: 24.hours.ago)

      expect { service.perform! }.not_to change(KanbanCard, :count)
      expect(terminal_card.reload).to have_attributes(kanban_stage_id: lost_stage.id, active: true)
    end

    it 'does not create a card when recurrence is disabled' do
      board.update!(won_recurrence_enabled: false)
      create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create a card when the contact has an active non-terminal card' do
      create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: regular_stage, contact: contact, inbox: inbox)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'evaluates the contact independently for each board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      create(:kanban_card, account: account, kanban_board: other_board, kanban_stage: other_stage, contact: contact, inbox: inbox)
      terminal_card = create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
      expect(KanbanCard.order(:id).last.recreated_from_card_id).to eq(terminal_card.id)
    end

    it 'uses the newest terminal card as the next recurrence reference' do
      first_terminal_card = create_terminal_card(won_stage, stage_entered_at: 2.days.ago)
      second_terminal_card = create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
      expect(KanbanCard.order(:id).last.recreated_from_card_id).to eq(second_terminal_card.id)
      expect(first_terminal_card.reload).to have_attributes(kanban_stage_id: won_stage.id, active: true)
    end

    it 'starts a new recurrence window from the card recreated by the previous one' do
      first_terminal_card = create_terminal_card(won_stage, stage_entered_at: 13.hours.ago)
      service.perform!
      second_card = KanbanCard.order(:id).last
      second_card.update!(kanban_stage: won_stage)
      second_card.update_column(:stage_entered_at, 13.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
      expect(KanbanCard.order(:id).last.recreated_from_card_id).to eq(second_card.id)
      expect(first_terminal_card.reload.recreated_from_card_id).to be_nil
    end

    it 'creates in the board and inbox passed to the service' do
      other_board = create(:kanban_board, account: account, won_recurrence_enabled: true, won_recurrence_window_hours: 1)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board, position: 1)
      other_won_stage = create(:kanban_stage, account: account, kanban_board: other_board, position: 2)
      other_lost_stage = create(:kanban_stage, account: account, kanban_board: other_board, position: 3)
      other_board.update!(won_stage: other_won_stage, lost_stage: other_lost_stage)
      terminal_card = create_terminal_card(other_won_stage, board: other_board, stage_entered_at: 2.hours.ago)
      other_inbox = create(:inbox, account: account, name: 'Other inbox')
      other_conversation = create(:conversation, account: account, contact: contact, inbox: other_inbox)

      described_class.new(conversation: other_conversation, kanban_board: other_board, inbox: other_inbox).perform!

      recreated_card = KanbanCard.order(:id).last
      expect(recreated_card).to have_attributes(
        kanban_board_id: other_board.id,
        kanban_stage_id: other_stage.id,
        inbox_id: other_inbox.id,
        recreated_from_card_id: terminal_card.id
      )
    end
  end

  def create_terminal_card(stage, stage_entered_at:, board: self.board)
    create(
      :kanban_card,
      account: account,
      kanban_board: board,
      kanban_stage: stage,
      contact: contact,
      inbox: inbox,
      subject: "Terminal opportunity #{stage.id} #{SecureRandom.hex(4)}"
    ).tap do |card|
      card.update_column(:stage_entered_at, stage_entered_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
