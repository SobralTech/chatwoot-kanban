require 'rails_helper'

RSpec.describe ConversationAccessUser do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'allows only account agents to be selected' do
    expect(build(:conversation_access_user, conversation: conversation, user: agent)).to be_valid
    expect(build(:conversation_access_user, conversation: conversation, user: administrator)).not_to be_valid
  end

  it 'marks selected users without base access as ineffective' do
    access_user = create(:conversation_access_user, conversation: conversation, user: agent)
    inbox.inbox_members.where(user: agent).destroy_all

    expect(access_user.effective_access?).to be(false)
  end
end
