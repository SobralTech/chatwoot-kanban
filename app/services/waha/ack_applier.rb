# Applies one WhatsApp delivery receipt to the exact Chatwoot message, multipart
# part and send attempt it belongs to, so the bubble's delivery indicator — still
# the agent-facing presentation — converges monotonically.
#
# Two GOWS traits shape this (see `receiptToMessageAck` in WAHA's
# session.gows.core.ts, which turns a whatsmeow receipt into `message.ack` for a
# direct chat and `message.ack.group` for a group):
#
#   * GOWS never emits SERVER (ack 1). whatsmeow receipts only carry DEVICE,
#     READ, PLAYED and server-error, so `sent` always comes from our own send
#     confirmation and never from a receipt.
#   * A group receipt is emitted per participant and carries no roster and no
#     participant count, so "delivered to / read by everyone" — what a group's
#     ticks mean in WhatsApp itself — cannot be derived from the receipt stream.
#     We keep the real granularity the payload does have (the participant) in
#     content_attributes['waha_group_acks'] and let the bubble mean "at least one
#     participant reached this state". A group receipt without a participant has
#     no usable granularity at all: it is logged and changes nothing.
class Waha::AckApplier
  GROUP_ACKS_KEY = 'waha_group_acks'.freeze

  RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
  # States WhatsApp has confirmed reached a device. A later error receipt for the
  # same stanza is stale and must not un-deliver them.
  CONFIRMED = %w[delivered read].freeze

  pattr_initialize [:channel!, :payload!, :group]

  # False means the receipt has nothing to anchor to yet (the mirror is still
  # being created), so the caller replays the event.
  def perform
    return true if status.nil?
    return false if message.nil?
    return true unless message.outgoing?

    message.with_lock do
      next unless record_group_participant

      part ? apply_part_ack : update_message_status(status)
    end
    true
  end

  private

  def status
    @status ||= case payload['ack']
                when -1 then 'failed'
                when 1 then 'sent'
                when 2 then 'delivered'
                when 3, 4 then 'read'
                end
  end

  def message
    resolve_target unless defined?(@message)
    @message
  end

  def attempt
    resolve_target unless defined?(@attempt)
    @attempt
  end

  def part
    resolve_target unless defined?(@part)
    @part
  end

  # The send attempt is the strongest correlation available: it matches only when
  # the receipt's stanza is a part's own pre-generated or WAHA-confirmed id, which
  # pins the receipt to one attempt and one part of a multipart send. Everything
  # else falls back to the canonical external mapping.
  def resolve_target
    @attempt = WahaDeliveryAttempt.find_by_correlated_id(channel: channel, wa_message_id: payload['id'], chat_jid: chat_jid)
    @part = @attempt&.correlated_part(payload['id'])
    @message = @attempt&.message || Waha::Anchoring.find_message(channel, payload['id'], chat_jid)
  end

  # GOWS builds an ack's id from the same parts as the message's own id, so the
  # chat it embeds is the one the mapping is keyed on. `from` is the fallback for
  # engines whose ack ids carry no chat segment.
  def chat_jid
    Waha::Anchoring.chat_jid_of(payload['id']) || payload['from'].presence
  end

  def apply_part_ack
    part.reload
    part.update!(ack_status: status) unless downgrade?(part.ack_status, status)
    update_message_status(attempt.aggregate_ack_status)
  end

  def update_message_status(new_status)
    return if new_status.nil? || new_status == message.status || downgrade?(message.status, new_status)
    return unless failure_transition_allowed?(new_status)

    return message.update!(status: :failed, external_error: 'WhatsApp reported a delivery error for this message') if new_status == 'failed'

    # Leaving `failed` behind clears the send error the same way a late send
    # confirmation does, so the bubble stops offering a retry it no longer needs.
    message.update!(status: new_status, external_error: nil)
  end

  # `sent -> delivered -> read` only ever moves forward. `failed` sits outside
  # that ladder: it can describe a part WhatsApp has not confirmed yet, never one
  # a receipt already proved reached a device.
  def downgrade?(current, new_status)
    return CONFIRMED.include?(current) if new_status == 'failed'

    RANK.fetch(new_status, 0) <= RANK.fetch(current, 0)
  end

  # A failed bubble is a claim about one specific send attempt, so only a receipt
  # tied back to that attempt may raise it or lift it. A receipt that resolved
  # through the external mapping alone proves the message but not the attempt, and
  # a stale one from an earlier attempt must leave the state untouched. A message
  # never tracked by an attempt (an echo of a send made outside Chatwoot) has no
  # stronger correlation to ask for, so its mapping is the evidence.
  def failure_transition_allowed?(new_status)
    return correlated_to_attempt? if new_status == 'failed'
    return true unless message.failed?

    accepted_attempt?
  end

  def correlated_to_attempt?
    return true if attempt.present?
    return true if message.waha_delivery_attempt.nil?

    Rails.logger.warn "[WAHA] Ignored uncorrelated failure ack #{log_context}"
    false
  end

  def accepted_attempt?
    return true if message.waha_delivery_attempt.nil?
    return false if attempt.nil?

    part ? part.sent? : attempt.sent?
  end

  # Group receipts are per participant, so each one advances only that
  # participant's entry. Returns false when the payload carries no participant —
  # the format has no usable granularity, so it produces a signal, not a state.
  def record_group_participant
    return true unless group

    participant = payload['participant'].presence || payload['to'].presence
    if participant.blank?
      Rails.logger.warn "[WAHA] Group ack without participant granularity #{log_context}"
      return false
    end

    acks = message.content_attributes[GROUP_ACKS_KEY] || {}
    unless downgrade?(acks[participant], status)
      message.update!(content_attributes: message.content_attributes.merge(GROUP_ACKS_KEY => acks.merge(participant => status)))
    end
    true
  end

  def log_context
    "channel=#{channel.id} inbox=#{channel.inbox.id} chat=#{chat_jid} source_id=#{payload['id']} ack=#{payload['ack']} " \
      "message=#{message&.id} attempt=#{attempt&.id} part=#{part&.position}"
  end
end
