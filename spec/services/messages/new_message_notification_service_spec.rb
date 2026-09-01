require 'rails_helper'

describe Messages::NewMessageNotificationService do
  context 'when message is not notifiable' do
    it 'will not create any notifications for activity messages' do
      message = build(:message, message_type: :activity)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end

    it 'will not create any notifications for private messages' do
      message = build(:message, message_type: :outgoing, private: true)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end
  end

  context 'when message is notifiable' do
    let(:account) { create(:account) }
    let(:inbox_agent_1) { create(:user, account: account) }
    let(:inbox_agent_2) { create(:user, account: account) }
    let(:outside_agent) { create(:user, account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      [inbox_agent_1, inbox_agent_2].each do |agent|
        create(:inbox_member, inbox: inbox, user: agent)
        notification_setting = agent.notification_settings.find_by(account_id: account.id)
        notification_setting.selected_email_flags = [:email_contact_message]
        notification_setting.selected_push_flags = [:push_contact_message]
        notification_setting.save!
      end
    end

    context 'when message is created by a contact' do
      let(:message) { create(:message, conversation: conversation, account: account) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates notifications for inbox members with access' do
        expect(inbox_agent_1.notifications.where(notification_type: 'contact_message', account: account,
                                                 primary_actor: message.conversation, secondary_actor: message)).to exist
        expect(inbox_agent_2.notifications.where(notification_type: 'contact_message', account: account,
                                                 primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'does not create notifications for users outside the inbox' do
        expect(outside_agent.notifications.where(notification_type: 'contact_message', account: account,
                                                 primary_actor: message.conversation, secondary_actor: message)).not_to exist
      end
    end

    context 'when message is outgoing' do
      let(:message) { create(:message, conversation: conversation, account: account, message_type: :outgoing, sender: inbox_agent_1) }

      it 'does not create contact message notifications' do
        expect do
          described_class.new(message: message).perform
        end.not_to change(Notification, :count)
      end
    end
  end

  describe 'query cost' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }

    def count_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
        count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
      end
      yield
      ActiveSupport::Notifications.unsubscribe(subscriber)
      count
    end

    def add_members(number)
      number.times { create(:inbox_member, inbox: inbox, user: create(:user, account: account)) }
    end

    def incoming_message
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, message_type: 'incoming', account: account, inbox: inbox, conversation: conversation)
    end

    it 'resolves conversation access without querying once per inbox member' do
      add_members(2)
      small = count_queries { described_class.new(message: incoming_message).perform }

      add_members(8)
      large = count_queries { described_class.new(message: incoming_message).perform }

      # Some cost is inherently per notified member; what must not grow is the
      # per-member membership and access lookups this service batches.
      expect(large - small).to be < (8 * 4)
    end

    it 'checks for already notified users in a single query' do
      add_members(4)
      message = incoming_message

      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
        queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION])
      end
      described_class.new(message: message).perform
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(queries.count { |sql| sql.include?('"notifications"."secondary_actor_id"') }).to eq(1)
    end
  end
end
