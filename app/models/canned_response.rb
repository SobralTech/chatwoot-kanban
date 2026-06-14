# == Schema Information
#
# Table name: canned_responses
#
#  id         :integer          not null, primary key
#  content    :text
#  mode       :string           default("insert"), not null
#  short_code :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#

class CannedResponse < ApplicationRecord
  MODES = %w[insert quick_send].freeze

  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }
  validates :mode, inclusion: { in: MODES }
  validate :quick_send_steps_present

  belongs_to :account
  has_many :canned_response_steps, -> { ordered }, dependent: :destroy, inverse_of: :canned_response, autosave: true

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }

  def quick_send?
    mode == 'quick_send'
  end

  private

  def quick_send_steps_present
    return unless quick_send?
    return if canned_response_steps.any?

    errors.add(:canned_response_steps, 'must be present')
  end
end
