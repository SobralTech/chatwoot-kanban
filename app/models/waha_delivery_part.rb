# One durable checkpoint for each WhatsApp message produced from one Chatwoot
# message. A part is confirmed before the sender advances to the next position,
# so retries can resume at the first pending row without repeating earlier work.
# == Schema Information
#
# Table name: waha_delivery_parts
#
#  id                       :bigint           not null, primary key
#  confirmed_at             :datetime
#  dispatched_at            :datetime
#  part_type                :integer          not null
#  position                 :integer          not null
#  status                   :integer          default("pending"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  attachment_id            :bigint
#  client_message_id        :string
#  external_id              :string
#  source_id                :text
#  waha_delivery_attempt_id :bigint           not null
#
# Indexes
#
#  index_waha_delivery_parts_on_attachment_id             (attachment_id)
#  index_waha_delivery_parts_on_attempt_and_position      (waha_delivery_attempt_id,position) UNIQUE
#  index_waha_delivery_parts_on_client_message_id         (client_message_id) WHERE (client_message_id IS NOT NULL)
#  index_waha_delivery_parts_on_waha_delivery_attempt_id  (waha_delivery_attempt_id)
#
# Foreign Keys
#
#  fk_rails_...  (attachment_id => attachments.id) ON DELETE => nullify
#  fk_rails_...  (waha_delivery_attempt_id => waha_delivery_attempts.id)
#
class WahaDeliveryPart < ApplicationRecord
  belongs_to :delivery_attempt, class_name: 'WahaDeliveryAttempt', foreign_key: :waha_delivery_attempt_id,
                                inverse_of: :delivery_parts
  belongs_to :attachment, optional: true

  enum :part_type, { text: 0, attachment: 1 }
  enum :status, { pending: 0, sent: 1 }

  validates :position, presence: true, uniqueness: { scope: :waha_delivery_attempt_id }
  validates :attachment, presence: true, if: :attachment?

  scope :in_delivery_order, -> { order(:position) }
end
