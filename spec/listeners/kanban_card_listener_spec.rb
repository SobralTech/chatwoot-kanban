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
