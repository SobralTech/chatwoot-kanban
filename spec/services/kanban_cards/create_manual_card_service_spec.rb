require 'rails_helper'

RSpec.describe KanbanCards::CreateManualCardService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account, use_opportunity_card_reads: true) }
  let(:kanban_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:card_subject) { '  New   opportunity  ' }
  let(:service) do
    described_class.new(
      account: account,
      user: user,
      kanban_board: kanban_board,
      kanban_stage: kanban_stage,
      contact: contact,
      inbox: inbox,
      subject: card_subject
    )
  end

  before do
    create(:inbox_member, user: user, inbox: inbox)
  end

  describe '#perform!' do
    it 'creates a valid manual card' do
      expect { service.perform! }.to change(KanbanCard, :count).by(1)

      expect(KanbanCard.last).to be_valid
    end

    it 'sets origin as manual' do
      card = service.perform!

      expect(card).to be_manual
    end

    it 'assigns the next active position in the selected stage' do
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 1)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 5)
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 6, active: false)

      card = service.perform!

      expect(card.position).to eq(6)
    end

    it 'normalizes subject through the KanbanCard model' do
      card = service.perform!

      expect(card.subject).to eq('New opportunity')
      expect(card.normalized_subject).to eq('new opportunity')
    end

    it 'allows the same contact and inbox with different subjects' do
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: contact,
        inbox: inbox,
        subject: 'Existing opportunity'
      )

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'rejects a normalized duplicate subject' do
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: contact,
        inbox: inbox,
        subject: 'new opportunity'
      )

      expect { service.perform! }.to raise_validation_error('Manual opportunity with this subject already exists')
    end

    it 'ignores inactive duplicates' do
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: contact,
        inbox: inbox,
        subject: 'new opportunity',
        active: false
      )

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'rejects an inactive board' do
      kanban_board.update!(active: false)

      expect { service.perform! }.to raise_validation_error('Board must be active')
    end

    it 'rejects a board without opportunity-card reads enabled' do
      kanban_board.update!(use_opportunity_card_reads: false)

      expect { service.perform! }.to raise_validation_error('Board must use opportunity card reads')
    end

    it 'rejects a stage from another board' do
      other_board = create(:kanban_board, account: account, use_opportunity_card_reads: true)
      other_stage = create(:kanban_stage, account: account, kanban_board: other_board)
      service = build_service(kanban_stage: other_stage)

      expect { service.perform! }.to raise_validation_error('Stage must belong to board')
    end

    it 'rejects an inactive stage' do
      kanban_stage.update!(active: false)

      expect { service.perform! }.to raise_validation_error('Stage must be active')
    end

    it 'rejects a contact from another account' do
      service = build_service(contact: create(:contact))

      expect { service.perform! }.to raise_validation_error('Contact must belong to account')
    end

    it 'rejects an inbox from another account' do
      service = build_service(inbox: create(:inbox))

      expect { service.perform! }.to raise_validation_error('Inbox must belong to account')
    end

    it 'rejects a user without inbox access' do
      user.inbox_members.destroy_all

      expect { service.perform! }.to raise_validation_error('User cannot access inbox')
    end

    it 'allows an admin to create a card without inbox membership' do
      admin = create(:user, account: account, role: :administrator)
      service = build_service(user: admin)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'rejects a blank subject after trim' do
      service = build_service(subject: '   ')

      expect { service.perform! }.to raise_validation_error("Subject can't be blank")
    end

    it 'links the most recent permitted matching conversation' do
      create(:conversation, account: account, contact: contact, inbox: inbox, last_activity_at: 2.days.ago)
      recent_conversation = create(:conversation, account: account, contact: contact, inbox: inbox, last_activity_at: 1.day.ago)

      card = service.perform!

      expect(card.conversation).to eq(recent_conversation)
    end

    it 'does not link a conversation from another inbox' do
      other_inbox = create(:inbox, account: account)
      create(:conversation, account: account, contact: contact, inbox: other_inbox)

      card = service.perform!
      expect(card.conversation_id).to be_nil
    end

    it 'does not link an unauthorized conversation' do
      create(:conversation, account: account, contact: contact, inbox: inbox)
      allow(ConversationPolicy).to receive(:new).and_return(instance_double(ConversationPolicy, show?: false))

      card = service.perform!
      expect(card.conversation_id).to be_nil
    end

    it 'creates card with conversation_id nil when no permitted conversation exists' do
      card = service.perform!

      expect(card.conversation_id).to be_nil
    end

    it 'does not create a ConversationKanbanState' do
      expect { service.perform! }.not_to change(ConversationKanbanState, :count)
    end

    it 'converts RecordNotUnique into a readable validation error' do
      allow(KanbanCard).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect { service.perform! }.to raise_validation_error('Manual opportunity with this subject already exists')
    end
  end

  def build_service(overrides = {})
    described_class.new(
      account: overrides.fetch(:account, account),
      user: overrides.fetch(:user, user),
      kanban_board: overrides.fetch(:kanban_board, kanban_board),
      kanban_stage: overrides.fetch(:kanban_stage, kanban_stage),
      contact: overrides.fetch(:contact, contact),
      inbox: overrides.fetch(:inbox, inbox),
      subject: overrides.fetch(:subject, card_subject)
    )
  end

  def raise_validation_error(message)
    raise_error(ActiveRecord::RecordInvalid, /#{Regexp.escape(message)}/)
  end
end
