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
        kanban_stage_id: board.default_stage_id,
        position: 1,
        active: true
      )
    end

    it 'generates the default subject from contact and inbox names' do
      board

      service.perform!

      expect(created_card.subject).to eq('Lead [Maria da Silva] - [WhatsApp Comercial]')
    end

    it 'uses fallback names when contact and inbox names are blank' do
      contact.update!(name: '')
      inbox.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations
      board

      service.perform!

      expect(created_card.subject).to eq("Lead [Contact ##{contact.id}] - [Inbox ##{inbox.id}]")
    end

    it 'sets normalized_subject to nil' do
      board

      service.perform!

      expect(created_card.normalized_subject).to be_nil
    end

    it 'assigns the next active position in the default stage' do
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: board.default_stage, position: 1)
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: board.default_stage, position: 5)

      service.perform!

      expect(created_card.position).to eq(6)
    end

    it 'ignores inactive cards when calculating position' do
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: board.default_stage, position: 8, active: false)

      service.perform!

      expect(created_card.position).to eq(1)
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

    it 'does not create when automation is disabled' do
      board.update!(auto_create_cards_from_conversations: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create when opportunity-card reads are disabled' do
      board.update!(use_opportunity_card_reads: false)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create without a default stage' do
      board.update!(default_stage: nil)

      expect { service.perform! }.not_to change(KanbanCard, :count)
    end

    it 'does not create when the default stage is inactive' do
      board.default_stage.update!(active: false)

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

    it 'does not create a ConversationKanbanState' do
      board

      expect { service.perform! }.not_to change(ConversationKanbanState, :count)
    end

    it 'returns summary counts' do
      existing_board = board
      create_automatic_card(kanban_board: existing_board)
      invalid_board = create_eligible_board
      invalid_board.update!(default_stage: nil)
      create_eligible_board

      expect(service.perform!).to eq(
        created: 1,
        skipped: {
          existing_card: 1,
          invalid_default_stage: 1
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
    stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
    kanban_board.update!(default_stage: stage)
    kanban_board
  end

  def create_automatic_card(kanban_board: board, active: true)
    create(
      :kanban_card,
      :conversation_origin,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: kanban_board.default_stage,
      conversation: conversation,
      active: active
    )
  end

  def created_card
    KanbanCard.conversation.find_by!(conversation: conversation)
  end
end
