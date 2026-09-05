# == Schema Information
#
# Table name: waha_delivery_attempts
#
#  id                :bigint           not null, primary key
#  attempt_count     :integer          default(0), not null
#  chat_jid          :string           not null
#  dispatched_at     :datetime
#  last_error        :text
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  channel_waha_id   :bigint           not null
#  client_message_id :string
#  external_id       :string
#  message_id        :bigint           not null
#
# Indexes
#
#  index_waha_delivery_attempts_on_channel_waha_id    (channel_waha_id)
#  index_waha_delivery_attempts_on_client_message_id  (channel_waha_id,client_message_id) UNIQUE WHERE (client_message_id IS NOT NULL)
#  index_waha_delivery_attempts_on_external_id        (channel_waha_id,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#  index_waha_delivery_attempts_on_message_id         (message_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (channel_waha_id => channel_waha.id)
#  fk_rails_...  (message_id => messages.id)
#
# One row per outgoing Chatwoot message routed through Waha::SendOnWahaService,
# tracking its persistent pending -> sending -> sent/failed delivery state.
# `client_message_id` is the pre-generated WhatsApp message id (GOWS
# `new-message-id`) used both as the send request's `id` and as the correlation
# key for the returning fromMe echo and for reconciliation after a lost response.
class WahaDeliveryAttempt < ApplicationRecord
  belongs_to :channel, class_name: 'Channel::Waha', foreign_key: :channel_waha_id, inverse_of: :delivery_attempts
  belongs_to :message
  has_many :delivery_parts, class_name: 'WahaDeliveryPart', dependent: :delete_all, inverse_of: :delivery_attempt

  enum :status, { pending: 0, sending: 1, sent: 2, failed: 3 }

  validates :chat_jid, presence: true

  def self.find_by_correlated_id(channel:, wa_message_id:)
    stanza = Waha::Anchoring.stanza_of(wa_message_id)
    return nil if stanza.blank?

    scope = where(channel: channel)
    chat_jid = Waha::Anchoring.chat_jid_of(wa_message_id)
    scope = scope.where(chat_jid: chat_jid) if chat_jid.present?
    scope.joins(:delivery_parts).find_by(waha_delivery_parts: { client_message_id: stanza }) ||
      scope.joins(:delivery_parts).find_by(waha_delivery_parts: { external_id: stanza }) ||
      scope.find_by(client_message_id: stanza) || scope.find_by(external_id: stanza)
  end

  # Transitions pending/failed -> sending and bumps the persisted attempt count,
  # guaranteeing at most one caller wins when two DeliverJob executions race for
  # the same message: the row lock serializes them and the loser sees `sending`.
  def claim!
    claimed = false
    with_lock do
      if pending? || failed?
        update!(status: :sending, attempt_count: attempt_count + 1)
        claimed = true
      end
    end
    claimed
  end

  # Atomically links a WAHA-confirmed message id to this attempt and its
  # Chatwoot message — from the HTTP response, from a correlated fromMe echo, or
  # from reconciliation. Idempotent: a second confirmation (e.g. the echo racing
  # the HTTP response) is a no-op once the attempt is already sent.
  def confirm_sent!(wa_message_id)
    part = correlated_part(wa_message_id)
    return confirm_part_sent!(part, wa_message_id) if part

    confirm_legacy_sent!(wa_message_id)
  end

  def confirm_part_sent!(part, wa_message_id)
    stanza = Waha::Anchoring.stanza_of(wa_message_id)
    with_lock do
      part.reload
      next if part.sent?

      WahaMessageMapping.create_canonical!(
        channel: channel, message: message, chat_jid: chat_jid, external_id: stanza, direction: :outgoing, part: part.position
      )
      part.update!(status: :sent, source_id: wa_message_id, external_id: stanza, confirmed_at: Time.current)
      set_anchor!(part, wa_message_id, stanza) if part.position == delivery_parts.minimum(:position)
      complete_delivery! unless delivery_parts.pending.exists?
    end
  end

  # The delivery state of a multipart message is the weakest state across its
  # parts: a message with a caption and two photos is only `read` once all three
  # WhatsApp messages were read. A part still waiting for its first receipt
  # leaves the aggregate undefined, so one part's ack is never shown as the
  # whole message's. `failed` is not a rung on that ladder — a single failed
  # part keeps the whole send visible as failed and resumable.
  def aggregate_ack_status
    states = delivery_parts.pluck(:ack_status)
    return nil if states.empty? || states.any?(&:nil?)
    return 'failed' if states.include?('failed')

    # The enum declares sent/delivered/read in ascending delivery order, so its
    # own values are the ranking.
    states.min_by { |state| WahaDeliveryPart.ack_statuses[state] }
  end

  def correlated_part(wa_message_id)
    stanza = Waha::Anchoring.stanza_of(wa_message_id)
    delivery_parts.find_by(client_message_id: stanza) || delivery_parts.find_by(external_id: stanza)
  end

  # Puts a claimed attempt back up for grabs after a failed send that still has
  # retries left. Guarded by the row lock so a fromMe echo that confirms the
  # send concurrently (the request did reach WAHA despite the local error)
  # cannot be clobbered back to `pending` by the losing local error handler.
  # Returns false (a no-op) when that race is what happened.
  def release_to_pending!(error_message = nil)
    with_lock { sent? ? false : update!(status: :pending, last_error: error_message) }
  end

  # Terminal failure after exhausting retries — same clobber guard and return
  # value as release_to_pending!.
  def mark_failed!(error_message)
    with_lock { sent? ? false : update!(status: :failed, last_error: error_message) }
  end

  private

  # Ticket 23 owns legacy migration. This fallback deliberately keeps an
  # already-running pre-multipart attempt confirmable without backfilling it.
  def confirm_legacy_sent!(wa_message_id)
    stanza = Waha::Anchoring.stanza_of(wa_message_id)
    with_lock do
      next if sent?

      message.update!(source_id: wa_message_id) if message.source_id.blank?
      WahaMessageMapping.create_canonical!(
        channel: channel, message: message, chat_jid: chat_jid, external_id: stanza, direction: :outgoing
      )
      update!(status: :sent, external_id: stanza)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    update!(status: :sent, external_id: stanza)
  end

  def set_anchor!(part, source_id, stanza)
    message.update!(source_id: source_id) if message.source_id.blank?
    update!(client_message_id: part.client_message_id, external_id: stanza)
  end

  def complete_delivery!
    message.update!(status: :sent, external_error: nil) if message.failed?
    update!(status: :sent, last_error: nil)
  end
end
