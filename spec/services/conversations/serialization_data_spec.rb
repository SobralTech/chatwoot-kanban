require 'rails_helper'

RSpec.describe Conversations::SerializationData, type: :service do
  it 'loads list message data in a fixed number of message queries' do
    account = create(:account)
    conversations = create_list(:conversation, 3, account: account, agent_last_seen_at: 1.day.ago)
    conversations.each do |conversation|
      create(:message, :incoming, account: account, inbox: conversation.inbox, conversation: conversation)
      create(:message, :outgoing, account: account, inbox: conversation.inbox, conversation: conversation)
    end
    sql_queries = []
    callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }

    result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      described_class.new(conversations: conversations).call
    end

    expect(result.last_messages.keys).to match_array(conversations.map(&:id))
    expect(result.last_non_activity_messages.keys).to match_array(conversations.map(&:id))
    message_queries = sql_queries.count { |sql| sql.include?('FROM "messages"') }
    expect(message_queries).to eq(3)
    expect(conversations.map(&:unread_incoming_messages_count)).to eq([1, 1, 1])
  end

  it 'preloads sender avatars so serializing senders issues no per-message queries' do
    account = create(:account)
    inbox = create(:inbox, account: account)
    conversations = create_list(:conversation, 3, account: account, inbox: inbox)
    conversations.each do |conversation|
      create(:message, :incoming, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact)
    end

    result = described_class.new(conversations: conversations).call

    sql_queries = []
    callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      result.last_messages.each_value { |message| message.sender.push_event_data }
    end

    expect(sql_queries.count { |sql| sql.include?('active_storage_attachments') }).to eq(0)
  end
end
