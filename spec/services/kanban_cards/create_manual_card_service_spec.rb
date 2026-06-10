require 'rails_helper'

RSpec.describe KanbanCards::CreateManualCardService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
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

    it 'emits kanban.card.created with a compact payload' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      card = service.perform!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        { account_id: account.id, board_id: kanban_board.id, stage_id: kanban_stage.id, card_id: card.id, conversation_id: nil }
      )
    end

    it 'sets origin as manual' do
      card = service.perform!

      expect(card).to be_manual
    end

    it 'sets stage_entered_at' do
      travel_to(Time.zone.parse('2026-06-09 12:00:00 UTC')) do
        card = service.perform!

        expect(card.stage_entered_at).to eq(Time.current)
      end
    end

    it 'inserts the card at the top of the selected stage' do
      create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 1)

      card = service.perform!

      expect(card.position).to eq(1)
    end

    it 'shifts existing active cards down in the selected stage' do
      first_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 1)
      second_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 2)

      service.perform!

      expect(first_card.reload.position).to eq(2)
      expect(second_card.reload.position).to eq(3)
    end

    it 'updates updated_at for mechanically shifted cards' do
      shifted_card = create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        position: 1,
        updated_at: 2.days.ago
      )

      travel_to(Time.zone.parse('2026-01-01 12:00:00 UTC')) do
        service.perform!
      end

      expect(shifted_card.reload.updated_at.to_i).to eq(Time.zone.parse('2026-01-01 12:00:00 UTC').to_i)
    end

    it 'does not query labels tags or taggings per shifted card' do
      baseline_query_count = labels_tags_taggings_query_count_for_manual_insert(card_count: 0)
      shifted_query_count = labels_tags_taggings_query_count_for_manual_insert(card_count: 5)

      expect(shifted_query_count).to eq(baseline_query_count)
    end

    it 'leaves inactive cards untouched when inserting at the top' do
      inactive_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: kanban_stage, position: 1, active: false)

      card = service.perform!

      expect(card.position).to eq(1)
      expect(inactive_card.reload.position).to eq(1)
    end

    it 'leaves cards in other stages untouched when inserting at the top' do
      other_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      other_stage_card = create(:kanban_card, account: account, kanban_board: kanban_board, kanban_stage: other_stage, position: 1)

      card = service.perform!

      expect(card.position).to eq(1)
      expect(other_stage_card.reload.position).to eq(1)
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

    it 'does not emit kanban.card.created when creation validation fails' do
      create(
        :kanban_card,
        account: account,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: contact,
        inbox: inbox,
        subject: 'new opportunity'
      )
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      expect { service.perform! }.to raise_validation_error('Manual opportunity with this subject already exists')
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(
        Events::Types::KANBAN_CARD_CREATED,
        anything,
        anything
      )
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

    it 'rejects a selected_agents board when agent is not a member' do
      kanban_board.update!(visibility_mode: 'selected_agents')

      expect { service.perform! }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'accepts a selected_agents board when agent is a member' do
      kanban_board.update!(visibility_mode: 'selected_agents')
      create(:kanban_board_member, account: account, kanban_board: kanban_board, user: user)

      expect { service.perform! }.to change(KanbanCard.manual, :count).by(1)
    end

    it 'accepts an admin on selected_agents board without membership' do
      admin = create(:user, account: account, role: :administrator)
      admin_service = described_class.new(
        account: account,
        user: admin,
        kanban_board: kanban_board,
        kanban_stage: kanban_stage,
        contact: contact,
        inbox: inbox,
        subject: card_subject
      )
      kanban_board.update!(visibility_mode: 'selected_agents')

      expect { admin_service.perform! }.to change(KanbanCard.manual, :count).by(1)
    end

    it 'creates a card when opportunity-card reads are disabled' do
      kanban_board.update!(use_opportunity_card_reads: false)

      expect { service.perform! }.to change(KanbanCard.manual, :count).by(1)
    end

    it 'rejects a stage from another board' do
      other_board = create(:kanban_board, account: account)
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

    it 'accepts inbox in all_inboxes mode' do
      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'accepts a selected inbox in selected_inboxes mode' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)

      expect { service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'rejects an unselected inbox in selected_inboxes mode' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')

      expect { service.perform! }.to raise_validation_error('Inbox is not allowed by board scope')
    end

    it 'allows admin to create within board scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      create(:kanban_board_inbox, account: account, kanban_board: kanban_board, inbox: inbox)
      admin = create(:user, account: account, role: :administrator)
      admin_service = build_service(user: admin)

      expect { admin_service.perform! }.to change(KanbanCard, :count).by(1)
    end

    it 'rejects admin when inbox is not in board scope' do
      kanban_board.update!(inbox_scope_mode: 'selected_inboxes')
      admin = create(:user, account: account, role: :administrator)
      admin_service = build_service(user: admin)

      expect { admin_service.perform! }.to raise_validation_error('Inbox is not allowed by board scope')
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

  def labels_tags_taggings_query_count_for_manual_insert(card_count:)
    board = create(:kanban_board, account: account)
    stage = create(:kanban_stage, account: account, kanban_board: board)
    create_labeled_cards(board, stage, card_count)
    insert_service = build_service(kanban_board: board, kanban_stage: stage, subject: "Shift query test #{card_count}")

    labels_tags_taggings_query_count(collect_sql_queries { insert_service.perform! })
  end

  def create_labeled_cards(board, stage, count)
    Array.new(count) do |index|
      create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, position: index + 1).tap do |card|
        card.update_labels(["label-#{index}"])
      end
    end
  end
end
