require 'rails_helper'

RSpec.describe KanbanCard do
  describe 'validations' do
    it 'allows a valid manual card' do
      card = build(:kanban_card)

      expect(card).to be_valid
    end

    it 'allows a valid conversation card' do
      card = build(:kanban_card, :conversation_origin)

      expect(card).to be_valid
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

    it 'rejects duplicate active conversation cards' do
      existing_card = create(:kanban_card, :conversation_origin)
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        conversation: existing_card.conversation
      )

      expect(card).not_to be_valid
      expect(card.errors[:conversation_id]).to be_present
    end

    it 'allows active conversation card recreation when existing card is inactive' do
      existing_card = create(:kanban_card, :conversation_origin, active: false)
      card = build(
        :kanban_card,
        :conversation_origin,
        account: existing_card.account,
        kanban_board: existing_card.kanban_board,
        kanban_stage: existing_card.kanban_stage,
        conversation: existing_card.conversation
      )

      expect(card).to be_valid
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
end
