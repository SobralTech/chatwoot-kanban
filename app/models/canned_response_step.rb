# == Schema Information
#
# Table name: canned_response_steps
#
#  id                 :bigint           not null, primary key
#  content            :text
#  position           :integer          default(0), not null
#  step_type          :string           default("text"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  canned_response_id :bigint           not null
#
# Indexes
#
#  index_canned_response_steps_on_canned_response_id               (canned_response_id)
#  index_canned_response_steps_on_canned_response_id_and_position  (canned_response_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (canned_response_id => canned_responses.id)
#

class CannedResponseStep < ApplicationRecord
  self.inheritance_column = :_type_disabled

  STEP_TYPES = %w[text image audio].freeze

  belongs_to :canned_response
  has_one_attached :file

  validates :step_type, inclusion: { in: STEP_TYPES }
  validates :position, presence: true
  validates :content, presence: true, if: :text?
  validate :file_required_for_media

  scope :ordered, -> { order(:position, :id) }

  def text?
    step_type == 'text'
  end

  def media?
    %w[image audio].include?(step_type)
  end

  def file_url
    return unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(file, only_path: true)
  end

  def file_name
    file.filename.to_s if file.attached?
  end

  def file_blob_id
    file.blob.signed_id if file.attached?
  end

  private

  def file_required_for_media
    return unless media?
    return if file.attached?

    errors.add(:file, 'must be attached')
  end
end
