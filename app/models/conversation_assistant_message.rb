# == Schema Information
#
# Table name: conversation_assistant_messages
#
#  id                  :bigint           not null, primary key
#  internal_note       :text
#  model               :string
#  question            :text             not null
#  sent_to_customer_at :datetime
#  sources             :jsonb            not null
#  status              :integer          default("pending"), not null
#  suggested_reply     :text
#  usage               :jsonb            not null
#  web_search_used     :boolean          default(FALSE), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  conversation_id     :bigint           not null
#  sent_message_id     :bigint
#  user_id             :bigint           not null
#
# Indexes
#
#  idx_conversation_assistant_messages_memory                (account_id,conversation_id,user_id,created_at)
#  index_conversation_assistant_messages_on_account_id       (account_id)
#  index_conversation_assistant_messages_on_conversation_id  (conversation_id)
#  index_conversation_assistant_messages_on_sent_message_id  (sent_message_id)
#  index_conversation_assistant_messages_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (sent_message_id => messages.id)
#  fk_rails_...  (user_id => users.id)
#

class ConversationAssistantMessage < ApplicationRecord
  QUESTION_MAX_LENGTH = 2000
  SUGGESTED_REPLY_MAX_LENGTH = 1500

  belongs_to :account
  belongs_to :conversation
  belongs_to :user
  belongs_to :sent_message, class_name: 'Message', optional: true

  enum status: { pending: 0, completed: 1, failed: 2, sent_to_customer: 3 }

  validates :question, presence: true, length: { maximum: QUESTION_MAX_LENGTH }
  validates :suggested_reply, length: { maximum: SUGGESTED_REPLY_MAX_LENGTH }, allow_blank: true
end
