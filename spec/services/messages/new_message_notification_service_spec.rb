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
end
