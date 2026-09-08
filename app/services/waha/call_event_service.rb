# Persists the lifecycle notifications GOWS emits for a direct WhatsApp call as
# Chatwoot activity messages. This is deliberately not a voice/video feature:
# it never opens media, creates a Call record, or offers a way to place/answer a
# call from Chatwoot.
class Waha::CallEventService
  EVENT_RESULTS = {
    'call.received' => :received,
    'call.accepted' => :accepted,
    'call.rejected' => :rejected
  }.freeze

  pattr_initialize [:channel!, :event!, :payload!]

  def perform
    policy = Waha::InboundEventPolicy.call(payload)
    Waha::InboundEventPolicy.observe(channel: channel, event: event, decision: policy)
    return unless policy.action == :represent

    @contact_inbox = Waha::ContactResolver.from_payload(channel: channel, jid: participant_jid, payload: contact_payload).perform
    persist
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_existing
  end

  private

  def persist
    Waha::Locking.with_chat_lock(channel, [participant_jid, @contact_inbox.source_id]) do
      existing = find_existing
      next existing if existing

      create_and_map_activity
    end
  end

  def create_and_map_activity
    ActiveRecord::Base.transaction do
      @contact_inbox.lock!
      @conversation = @contact_inbox.conversations.last || create_conversation
      existing = find_existing
      next existing if existing

      message = create_activity
      WahaMessageMapping.create_canonical!(
        channel: channel,
        message: message,
        chat_jid: @contact_inbox.source_id,
        external_id: external_id,
        direction: :incoming,
        event_type: :call,
        provider_id: "waha-call:#{external_id}",
        participant_jid: participant_jid
      )
      message
    end
  end

  def participant_jid
    @participant_jid ||= Waha::Jid.phone_jid(payload['from']) || payload['from']
  end

  def contact_payload
    {
      'fromMe' => false,
      '_data' => payload['_data'] || {}
    }
  end

  def external_id
    "#{payload['id']}:#{event}"
  end

  def find_existing
    return unless @contact_inbox

    WahaMessageMapping.find_mapping(
      channel: channel,
      chat_jid: [@contact_inbox.source_id, participant_jid].compact.uniq,
      external_id: external_id,
      event_type: :call
    )&.message
  end

  def create_conversation
    ::Conversation.create!(
      account_id: channel.inbox.account_id,
      inbox_id: channel.inbox.id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id
    )
  end

  def create_activity
    @conversation.messages.create!(
      account_id: channel.inbox.account_id,
      inbox_id: channel.inbox.id,
      message_type: :activity,
      content: content,
      content_attributes: { waha_call: call_attributes }
    )
  end

  def content
    I18n.t(
      'conversations.messages.waha_call.event',
      direction: I18n.t("conversations.messages.waha_call.direction.#{direction}"),
      kind: I18n.t("conversations.messages.waha_call.kind.#{video? ? :video : :voice}"),
      result: I18n.t("conversations.messages.waha_call.result.#{result}"),
      duration: duration_text
    )
  end

  # GOWS's public CallData contract currently has no duration. Keep this small
  # compatibility extraction so a future GOWS payload that adds one remains
  # visible without changing the identity or the display contract.
  def duration
    value = payload['duration'] || payload.dig('_data', 'Duration') || payload.dig('_data', 'duration')
    return unless value.to_f.positive?

    value.to_i
  end

  def duration_text
    return '' unless duration

    I18n.t('conversations.messages.waha_call.duration', duration: duration)
  end

  def call_attributes
    {
      'id' => payload['id'],
      'direction' => direction.to_s,
      'participant_jid' => participant_jid,
      'result' => result.to_s,
      'is_video' => video?,
      'duration' => duration,
      'event' => event
    }.compact
  end

  def direction
    :incoming
  end

  def result
    EVENT_RESULTS.fetch(event)
  end

  def video?
    payload['isVideo'] == true
  end
end
