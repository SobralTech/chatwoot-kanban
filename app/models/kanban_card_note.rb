# == Schema Information
#
# Table name: kanban_card_notes
#
#  id             :bigint           not null, primary key
#  content        :text             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  kanban_card_id :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_kanban_card_notes_on_account_id                     (account_id)
#  index_kanban_card_notes_on_kanban_card_id                 (kanban_card_id)
#  index_kanban_card_notes_on_kanban_card_id_and_created_at  (kanban_card_id,created_at)
#  index_kanban_card_notes_on_user_id                        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_card_id => kanban_cards.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class KanbanCardNote < ApplicationRecord
  MAX_ATTACHMENTS = 5
  MAX_ATTACHMENT_SIZE = 20.megabytes

  belongs_to :account
  belongs_to :kanban_card
  belongs_to :user, optional: true
  has_many_attached :attachments

  validates :content, presence: true, length: { maximum: 10_000 }
  validate :validate_account_consistency
  validate :validate_attachments

  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  private

  def validate_attachments
    errors.add(:attachments, I18n.t('errors.kanban_card_note.attachments.too_many')) if attachments.size > MAX_ATTACHMENTS

    attachments.blobs.each do |blob|
      next unless blob.byte_size > MAX_ATTACHMENT_SIZE

      errors.add(:attachments, I18n.t('errors.kanban_card_note.attachments.too_large'))
    end
  end

  def validate_account_consistency
    validate_account_for(:kanban_card)
    return if user.blank? || user.account_users.exists?(account_id: account_id)

    errors.add(:user, :invalid)
  end

  def validate_account_for(association_name)
    associated_record = public_send(association_name)
    return if associated_record.blank? || associated_record.account_id == account_id

    errors.add(association_name, :invalid)
  end
end
