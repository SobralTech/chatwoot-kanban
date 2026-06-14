require 'rails_helper'

RSpec.describe KanbanCards::CreateFromConversationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva') }
  let(:inbox) { create(:inbox, account: account, name: 'Sales Inbox') }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:card_subject) { nil }
  let(:due_at) { nil }
  let(:labels) { [] }
  let(:service) { build_service }

  before do
    create(:inbox_member, user: user, inbox: inbox)
  end

  describe '#perform!' do
    it 'creates a conversation-origin card at the top of the selected stage' do
      expect { service.perform! }.to change(KanbanCard.conversation, :count).by(1)

      expect(KanbanCard.last).to have_attributes(
        origin: 'conversation',
        kanban_stage_id: kanban_stage.id,
        conversation_id: conversation.id,
        position: 1
      )
    end

    it 'sets stage_entered_at' do
      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        card = service.perform!

        expect(card.stage_entered_at).to eq(Time.current)
      end
    end

    it 'shifts existing active cards down' do
      first_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 1)
      second_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 2)

      service.perform!

      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'uses conversation contact and inbox' do
      card = service.perform!

      expect(card).to have_attributes(contact_id: contact.id, inbox_id: inbox.id)
    end

    it 'uses the default subject when subject is blank' do
      card = build_service(subject: '   ').perform!

      expect(card.subject).to eq('Maria Silva - Sales Inbox')
    end

    it 'uses fallback names in the default subject' do
      allow(contact).to receive(:name).and_return(nil)
      allow(inbox).to receive(:name).and_return(nil)
      allow(conversation).to receive(:contact).and_return(contact)
      allow(conversation).to receive(:inbox).and_return(inbox)

      card = service.perform!

      expect(card.subject).to eq("Contact ##{contact.id} - Inbox ##{inbox.id}")
    end

    it 'accepts a custom trimmed subject' do
      card = build_service(subject: '  Enterprise   renewal  ').perform!

      expect(card.subject).to eq('Enterprise renewal')
    end

    it 'accepts due_at ISO8601' do
      card = build_service(due_at: '2026-06-07T18:00:00-03:00').perform!

      expect(card.due_at).to eq(Time.zone.parse('2026-06-07T18:00:00-03:00'))
    end

    it 'accepts due_at null' do
      card = build_service(due_at: nil).perform!

      expect(card.due_at).to be_nil
    end

    it 'persists existing labels' do
      create(:label, account: account, title: 'urgente')
      create(:label, account: account, title: 'vendas')

      card = build_service(labels: %w[urgente vendas]).perform!

      expect(card.label_list).to contain_exactly('urgente', 'vendas')
    end

    it 'accepts empty labels' do
      card = build_service(labels: []).perform!

      expect(card.label_list).to be_empty
    end

    it 'deduplicates labels' do
      create(:label, account: account, title: 'urgente')

      card = build_service(labels: %w[urgente urgente]).perform!

      expect(card.label_list).to contain_exactly('urgente')
    end

    it 'rejects a missing label' do
      expect { build_service(labels: ['missing']).perform! }.to raise_validation_error('Labels must exist in account')
    end

    it 'rejects a label from another account' do
      create(:label, title: 'external')

      expect { build_service(labels: ['external']).perform! }.to raise_validation_error('Labels must exist in account')
    end

    it 'does not create a card when labels are invalid' do
      expect do
        build_service(labels: ['missing']).perform!
      rescue ActiveRecord::RecordInvalid
        nil
      end.not_to change(KanbanCard, :count)
    end

    it 'does not emit kanban.card.created when labels are invalid' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      expect { build_service(labels: ['missing']).perform! }.to raise_validation_error('Labels must exist in account')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'rejects an active duplicate card for the same board conversation and subject' do
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        subject: 'Maria Silva - Sales Inbox'
      )

      expect { service.perform! }.to raise_validation_error('Conversation already has an opportunity with this subject on this board')
    end

    it 'allows another card for the same board and conversation with a different subject' do
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        subject: 'Enterprise renewal'
      )

      expect { build_service(subject: 'Expansion project').perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'rejects an inactive historical duplicate card for the same board conversation and subject' do
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        subject: 'Maria Silva - Sales Inbox',
        active: false
      )

      expect { service.perform! }.to raise_validation_error('Conversation already has an opportunity with this subject on this board')
    end

    it 'rejects an inactive board' do
      kanban_board.update!(active: false)

      expect { service.perform! }.to raise_validation_error('Board must be active')
    end

    it 'rejects a selected_agents board when agent is not a member' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      expect { service.perform! }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'accepts a selected_agents board when agent is a member' do
      kanban_board.update!(visibility_mode: 'selected_agents')
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: user)

      expect { service.perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'accepts an admin on selected_agents board without membership' do
      admin = create(:user, account: account, role: :administrator)
      create(:inbox_member, user: admin, inbox: inbox)
      admin_service = build_service(user: admin)
      kanban_board.update!(visibility_mode: 'selected_agents')

      expect { admin_service.perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'rejects a stage from another board' do
      other_board = create(:kanban_board, account: account)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

      expect { build_service(kanban_stage: other_stage).perform! }.to raise_validation_error('Stage must belong to board')
    end

    it 'rejects an inactive stage' do
      kanban_stage.update!(active: false)

      expect { service.perform! }.to raise_validation_error('Stage must be active')
    end

    it 'rejects a conversation from another account' do
      other_conversation = create(:conversation)

      expect { build_service(conversation: other_conversation).perform! }.to raise_validation_error('Conversation must belong to account')
    end

    it 'rejects an unauthorized conversation' do
      user.inbox_members.destroy_all

      expect { service.perform! }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'accepts conversation in all_inboxes mode' do
      expect { service.perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'accepts conversation when inbox is selected in selected_inboxes mode' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      expect { service.perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'rejects conversation when inbox is not in selected_inboxes mode' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')

      expect { service.perform! }.to raise_validation_error('Conversation inbox is not allowed by board scope')
    end

    it 'accepts admin conversation creation within board scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)
      admin = create(:user, account: account, role: :administrator)
      create(:inbox_member, user: admin, inbox: inbox)
      admin_service = build_service(user: admin)

      expect { admin_service.perform! }.to change(KanbanCard.conversation, :count).by(1)
    end

    it 'rejects admin conversation creation when inbox is not in board scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      admin = create(:user, account: account, role: :administrator)
      create(:inbox_member, user: admin, inbox: inbox)
      admin_service = build_service(user: admin)

      expect { admin_service.perform! }.to raise_validation_error('Conversation inbox is not allowed by board scope')
    end

    it 'emits kanban.card.created with a compact payload' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      card = service.perform!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        {
          account_id: account.id,
          board_id: kanban_board.id,
          stage_id: kanban_stage.id,
          card_id: card.id,
          conversation_id: conversation.id
        }
      )
    end

    it 'does not emit kanban.card.created when creation fails' do
      create(
        :kanban_card,
        :conversation_origin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        conversation: conversation,
        subject: 'Maria Silva - Sales Inbox'
      )
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      expect { service.perform! }.to raise_validation_error('Conversation already has an opportunity with this subject on this board')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
    end

    it 'does not create a ConversationKanbanState' do
      expect { service.perform! }.not_to change(ConversationKanbanState, :count)
    end
  end

  def build_service(overrides = {})
    described_class.new(
      account: overrides.fetch(:account, account),
      user: overrides.fetch(:user, user),
      conversation: overrides.fetch(:conversation, conversation),
      kanban_board: overrides.fetch(:kanban_board, kanban_board),
      kanban_stage: overrides.fetch(:kanban_stage, kanban_stage),
      subject: overrides.fetch(:subject, card_subject),
      due_at: overrides.fetch(:due_at, due_at),
      labels: overrides.fetch(:labels, labels)
    )
  end

  def raise_validation_error(message)
    raise_error(ActiveRecord::RecordInvalid, /#{Regexp.escape(message)}/)
  end
end
