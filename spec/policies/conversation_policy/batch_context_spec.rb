require 'rails_helper'

RSpec.describe ConversationPolicy::BatchContext do
  # Mirrors the per-user implementation that ran before batching, so the two can be compared.
  def unbatched_tokens(account, conversation)
    account.users.to_a.select do |user|
      ConversationPolicy.new(
        { user: user, account: account, account_user: user.account_users.find_by(account: account) }, conversation
      ).show?
    end.map(&:pubsub_token)
  end

  def batched_tokens(account, conversation)
    ActionCableListener.instance.send(:authorized_user_tokens, account, conversation)
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, payload|
      count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
    end
    yield
    ActiveSupport::Notifications.unsubscribe(subscriber)
    count
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  describe 'parity with per-user policy evaluation' do
    let!(:administrator) { create(:user, account: account, role: :administrator) }
    let!(:inbox_agent) { create(:user, account: account, role: :agent) }
    let!(:listed_agent) { create(:user, account: account, role: :agent) }
    let!(:team_agent) { create(:user, account: account, role: :agent) }
    let!(:unrelated_agent) { create(:user, account: account, role: :agent) }
    let(:team) { create(:team, account: account) }

    before do
      create(:inbox_member, inbox: inbox, user: inbox_agent)
      create(:inbox_member, inbox: inbox, user: listed_agent)
      create(:inbox_member, inbox: other_inbox, user: unrelated_agent)
      create(:team_member, team: team, user: team_agent)
    end

    %i[all_agents selected_agents admins_only].each do |access_mode|
      it "returns the same tokens as per-user evaluation for #{access_mode} conversations" do
        conversation = create(:conversation, account: account, inbox: inbox)
        conversation.update!(access_mode: access_mode)
        create(:conversation_access_user, conversation: conversation, user: listed_agent, account: account) if access_mode == :selected_agents

        expect(batched_tokens(account, conversation).sort).to eq(unbatched_tokens(account, conversation).sort)
      end

      it "returns the same tokens as per-user evaluation for #{access_mode} conversations assigned to a team" do
        conversation = create(:conversation, account: account, inbox: other_inbox, team: team)
        conversation.update!(access_mode: access_mode)
        create(:conversation_access_user, conversation: conversation, user: listed_agent, account: account) if access_mode == :selected_agents

        expect(batched_tokens(account, conversation).sort).to eq(unbatched_tokens(account, conversation).sort)
      end
    end

    it 'grants access to administrators and inbox members but not unrelated agents' do
      conversation = create(:conversation, account: account, inbox: inbox)

      tokens = batched_tokens(account, conversation)

      expect(tokens).to include(administrator.pubsub_token, inbox_agent.pubsub_token)
      expect(tokens).not_to include(unrelated_agent.pubsub_token)
    end
  end

  describe 'query cost' do
    it 'does not issue more queries as the account grows' do
      create(:user, account: account, role: :administrator)
      conversation = create(:conversation, account: account, inbox: inbox)

      5.times { create(:inbox_member, inbox: inbox, user: create(:user, account: account, role: :agent)) }
      baseline = count_queries { batched_tokens(account.reload, conversation) }

      45.times { create(:inbox_member, inbox: inbox, user: create(:user, account: account, role: :agent)) }
      grown = count_queries { batched_tokens(account.reload, conversation) }

      expect(grown).to eq(baseline)
    end
  end
end
