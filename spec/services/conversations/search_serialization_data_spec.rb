require 'rails_helper'

RSpec.describe Conversations::SearchSerializationData, type: :service do
  it 'loads the last useful message for every conversation in one message query' do
    account = create(:account)
    conversations = create_list(:conversation, 3, account: account)
    conversations.each do |conversation|
      create(:message, :incoming, account: account, inbox: conversation.inbox, conversation: conversation)
      create(:message, :outgoing, account: account, inbox: conversation.inbox, conversation: conversation)
    end
    sql_queries = []
    callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }

    result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      described_class.new(conversations: conversations).call
    end

    expect(result.keys).to match_array(conversations.map(&:id))
    expect(sql_queries.count { |sql| sql.include?('FROM "messages"') }).to eq(1)
  end
end
