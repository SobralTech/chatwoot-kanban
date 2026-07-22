class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  CONVERSATION_PAYLOAD_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED,
    CONVERSATION_CREATED,
    CONVERSATION_CONTACT_CHANGED,
    MESSAGE_CREATED,
    MESSAGE_UPDATED,
    FIRST_REPLY_CREATED
  ].freeze

  def perform(members, event_name, data, conversation_id = nil)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    broadcast_to_members(authorized_members(members, event_name, conversation_id), event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    conversation.push_event_data.merge(account_id: data[:account_id])
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end

  def authorized_members(members, event_name, conversation_id)
    return members unless CONVERSATION_PAYLOAD_EVENTS.include?(event_name) && conversation_id.present?

    conversation = Conversation.find_by(id: conversation_id)
    return [] if conversation.blank?

    account = conversation.account

    members.select do |member|
      user = User.find_by(pubsub_token: member)
      next true if user.blank?

      account_user = user.account_users.find_by(account: account)
      ConversationPolicy.new({ user: user, account: account, account_user: account_user }, conversation).show?
    end
  end
end
