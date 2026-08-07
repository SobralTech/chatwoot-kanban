require 'rails_helper'

RSpec.describe KanbanCardListener do
  let(:listener) { described_class.instance }
  let(:conversation) { create(:conversation) }
  let(:event_name) { :'conversation.created' }

  describe '#conversation_created' do
    it 'enqueues automatic card creation with the conversation id' do
      event = Events::Base.new(event_name, Time.zone.now, conversation: conversation)

      expect { listener.conversation_created(event) }.to have_enqueued_job(KanbanCards::AutoCreateFromConversationJob)
        .with(conversation.id)
        .on_queue('low')
    end

    it 'does not enqueue when the conversation payload is missing' do
      event = Events::Base.new(event_name, Time.zone.now, {})

      expect { listener.conversation_created(event) }.not_to have_enqueued_job(KanbanCards::AutoCreateFromConversationJob)
    end
  end

  describe '#message_created' do
    let(:kanban_board) { create(:kanban_board, account: conversation.account) }
    let(:message) { create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox) }

    it 'enqueues recurrence evaluation for an inbound message' do
      event = Events::Base.new(:'message.created', Time.zone.now, message: message)
      kanban_board

      expect { listener.message_created(event) }.to have_enqueued_job(KanbanCards::EvaluateContactRecurrenceJob)
        .with(conversation.id, anything, conversation.inbox_id)
        .on_queue('low')
    end

    it 'ignores outgoing messages' do
      message.update!(message_type: :outgoing, sender: create(:user, account: conversation.account))
      event = Events::Base.new(:'message.created', Time.zone.now, message: message)

      expect { listener.message_created(event) }.not_to have_enqueued_job(KanbanCards::EvaluateContactRecurrenceJob)
    end

    it 'ignores private notes' do
      message.update!(private: true)
      event = Events::Base.new(:'message.created', Time.zone.now, message: message)

      expect { listener.message_created(event) }.not_to have_enqueued_job(KanbanCards::EvaluateContactRecurrenceJob)
    end

    it 'ignores activity messages' do
      message.update!(message_type: :activity)
      event = Events::Base.new(:'message.created', Time.zone.now, message: message)

      expect { listener.message_created(event) }.not_to have_enqueued_job(KanbanCards::EvaluateContactRecurrenceJob)
    end

    it 'ignores messages performed by an automation rule' do
      automation_rule = create(:automation_rule, account: conversation.account)
      event = Events::Base.new(:'message.created', Time.zone.now, message: message, performed_by: automation_rule)

      expect { listener.message_created(event) }.not_to have_enqueued_job(KanbanCards::EvaluateContactRecurrenceJob)
    end

    context 'when the contact has a terminal card on the board' do
      let(:kanban_board) do
        create(:kanban_board, account: conversation.account, won_recurrence_enabled: true, won_recurrence_window_hours: 1)
      end
      let(:regular_stage) { create(:kanban_stage, account: conversation.account, kanban_board: kanban_board, position: 1) }
      let!(:won_stage) { create(:kanban_stage, account: conversation.account, kanban_board: kanban_board, position: 2) }
      let!(:terminal_card) do
        create(
          :kanban_card,
          account: conversation.account,
          kanban_board: kanban_board,
          kanban_stage: won_stage,
          contact: conversation.contact,
          inbox: conversation.inbox,
          subject: 'Terminal opportunity'
        ).tap do |card|
          card.update_column(:stage_entered_at, 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      before do
        regular_stage
        kanban_board.update!(won_stage: won_stage)
        terminal_card
      end

      it 'creates the card from an inbound message in an existing conversation' do
        event = Events::Base.new(:'message.created', Time.zone.now, message: message)

        expect do
          perform_enqueued_jobs { listener.message_created(event) }
        end.to change(KanbanCard, :count).by(1)

        expect(KanbanCard.order(:id).last.recreated_from_card_id).to eq(terminal_card.id)
      end
    end
  end

  describe 'async dispatcher registration' do
    it 'registers the Kanban listener' do
      expect(async_listener_classes).to include(described_class)
    end

    it 'keeps existing async listeners registered' do
      expect(async_listener_classes).to include(
        AutomationRuleListener,
        CampaignListener,
        CsatSurveyListener,
        HookListener,
        InstallationWebhookListener,
        NotificationListener,
        ParticipationListener,
        Conversations::UnreadCounts::Listener,
        ReportingEventListener,
        WebhookListener
      )
    end
  end

  def async_listener_classes
    AsyncDispatcher.new.listeners.map(&:class)
  end
end
