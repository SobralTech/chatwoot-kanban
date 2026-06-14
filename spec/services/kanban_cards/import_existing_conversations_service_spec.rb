require 'rails_helper'

RSpec.describe KanbanCards::ImportExistingConversationsService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp') }
  let(:other_inbox) { create(:inbox, account: account, name: 'Support') }
  let(:board) { create(:kanban_board, account: account, auto_create_cards_from_conversations: true) }
  let!(:stage) { create(:kanban_stage, account: account, kanban_board: board, position: 1) }

  describe '#perform!' do
    it 'imports open conversations into the first active stage' do
      conversation = create(:conversation, account: account, inbox: inbox)

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .to change(KanbanCard.conversation, :count).by(1)

      expect(KanbanCard.last).to have_attributes(
        account_id: account.id,
        kanban_board_id: board.id,
        kanban_stage_id: stage.id,
        conversation_id: conversation.id,
        contact_id: conversation.contact_id,
        inbox_id: inbox.id,
        origin: 'conversation',
        active: true
      )
    end

    it 'uses open conversations only' do
      create(:conversation, account: account, inbox: inbox, status: 'open')
      create(:conversation, account: account, inbox: inbox, status: 'resolved')

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .to change(KanbanCard.conversation, :count).by(1)
    end

    it 'does not import conversations from another account' do
      create(:conversation, account: account, inbox: inbox)
      create(:conversation)

      described_class.new(account: account, kanban_board: board).perform!

      expect(KanbanCard.conversation.pluck(:account_id)).to contain_exactly(account.id)
    end

    it 'does not duplicate existing conversation cards' do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:kanban_card, :conversation_origin, account: account, kanban_board: board, kanban_stage: stage, conversation: conversation)

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .not_to change(KanbanCard.conversation, :count)
    end

    it 'reactivates an inactive conversation card instead of duplicating it' do
      conversation = create(:conversation, account: account, inbox: inbox)
      card = create(
        :kanban_card,
        :conversation_origin,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation,
        active: false,
        position: 1
      )

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .not_to change(KanbanCard.conversation, :count)

      expect(card.reload).to have_attributes(
        active: true,
        kanban_stage_id: stage.id
      )
    end

    it 'is idempotent across repeated runs' do
      create(:conversation, account: account, inbox: inbox)

      service = described_class.new(account: account, kanban_board: board)
      service.perform!

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .not_to change(KanbanCard.conversation, :count)
    end

    it 'respects selected inbox scope' do
      board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: board, inbox: inbox)
      selected_conversation = create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: other_inbox)

      described_class.new(account: account, kanban_board: board).perform!

      expect(KanbanCard.conversation.pluck(:conversation_id)).to contain_exactly(selected_conversation.id)
    end

    it 'excludes group conversations when ignore_groups is true' do
      group_contact = create(:contact, account: account, identifier: '5511999999999@g.us')
      group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: '5511999999999@g.us')
      create(
        :conversation,
        account: account,
        contact: group_contact,
        contact_inbox: group_contact_inbox,
        inbox: inbox,
        identifier: '5511999999999@g.us'
      )
      regular_conversation = create(:conversation, account: account, inbox: inbox)

      described_class.new(account: account, kanban_board: board, ignore_groups: true).perform!

      expect(KanbanCard.conversation.pluck(:conversation_id)).to contain_exactly(regular_conversation.id)
    end

    it 'imports group conversations when ignore_groups is false' do
      group_contact = create(:contact, account: account, identifier: '5511999999999@g.us')
      group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: '5511999999999@g.us')
      create(
        :conversation,
        account: account,
        contact: group_contact,
        contact_inbox: group_contact_inbox,
        inbox: inbox,
        identifier: '5511999999999@g.us'
      )

      expect { described_class.new(account: account, kanban_board: board, ignore_groups: false).perform! }
        .to change(KanbanCard.conversation, :count).by(1)
    end

    it 'processes conversations in batches' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      create_list(:conversation, 3, account: account, inbox: inbox)

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .to change(KanbanCard.conversation, :count).by(3)
    end

    it 'does nothing when there is no active stage' do
      stage.update!(active: false)
      create(:conversation, account: account, inbox: inbox)

      expect { described_class.new(account: account, kanban_board: board).perform! }
        .not_to change(KanbanCard.conversation, :count)
    end
  end

  describe '#estimated_count' do
    it 'returns the eligible conversation count' do
      create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, status: 'resolved')

      expect(described_class.new(account: account, kanban_board: board).estimated_count).to eq(1)
    end
  end
end
