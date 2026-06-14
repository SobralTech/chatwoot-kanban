FactoryBot.define do
  factory :conversation_assistant_message do
    account
    conversation { create(:conversation, account: account) }
    user { create(:user, account: account, role: :agent) }
    question { 'Is this toner compatible?' }
    suggested_reply { 'This toner is compatible with the printer.' }
    internal_note { 'Check the exact printer revision before confirming.' }
    sources { [] }
    model { 'gpt-4.1-mini' }
    web_search_used { false }
    usage { { 'prompt_tokens' => 10, 'completion_tokens' => 5, 'total_tokens' => 15 } }
    status { :completed }
  end
end
