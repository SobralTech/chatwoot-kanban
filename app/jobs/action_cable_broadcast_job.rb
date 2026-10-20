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
    broadcast_data = conversation.push_event_data.merge(account_id: data[:account_id])
    if event_name == ASSIGNEE_CHANGED
      # Keep the original assignment together even when the conversation is
      # refreshed. The dashboard checks its identity against the current owner.
      # Other events omit this field so unrelated updates cannot overwrite it.
      broadcast_data[:assignment] = {
        automatic: data[:automatic_assignment] == true,
        assignee_id: data.dig(:meta, :assignee, :id),
        assignee_type: data.dig(:meta, :assignee_type),
        updated_at: data[:updated_at]
      }
    end
    broadcast_data
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
    batch_context = ConversationPolicy::BatchContext.new(account, conversation)
    users_by_token = User.where(pubsub_token: members).index_by(&:pubsub_token)

    members.select do |member|
      user = users_by_token[member]
      # contact tokens have no matching user and are always allowed through
      next true if user.blank?

      user_context = {
        user: user, account: account, account_user: batch_context.account_user_for(user.id), batch_context: batch_context
      }
      ConversationPolicy.new(user_context, conversation).show?
    end
  end
end
