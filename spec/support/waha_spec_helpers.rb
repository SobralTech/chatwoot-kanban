module WahaSpecHelpers
  # Captures the operational signals emitted while the block runs, as
  # [signal_name, payload] pairs. Assertions read the payload's fields, never a
  # log line's wording, so the signal contract is what is pinned down here.
  def capture_waha_signals
    captured = []
    subscriber = ActiveSupport::Notifications.subscribe(/^waha\./) do |name, _start, _finish, _id, payload|
      captured << [name.delete_prefix('waha.').to_sym, payload]
    end
    yield
    captured
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def waha_signal(signals, name)
    signals.select { |signal, _payload| signal == name }.map(&:last)
  end

  def waha_messages(provider_id, scope = Message.all)
    scope.where(id: WahaMessageMapping.where(provider_id: provider_id).select(:message_id))
  end

  def create_waha_attempt(**attributes)
    attempt = WahaDeliveryAttempt.create!(**attributes.except(:client_message_id, :external_id))
    attempt.delivery_parts.create!(position: 0, part_type: :text, status: attempt.sent? ? :sent : :pending,
                                   client_message_id: attributes[:client_message_id], external_id: attributes[:external_id])
    attempt
  end

  # Creates a persisted canonical fixture without writing Message#source_id.
  def create_waha_message(*traits, source_id: nil, **attributes)
    legacy_anchor = attributes.fetch(:additional_attributes, {}).delete('edit_of')
    message = create(:message, *traits, **attributes)
    return message if source_id.blank?

    channel = message.inbox.channel
    chat = Waha::Anchoring.chat_jid_of(source_id) || message.conversation.contact_inbox.source_id
    anchor = Waha::Anchoring.find_message(channel, legacy_anchor, chat) if legacy_anchor
    WahaMessageMapping.create_canonical!(
      channel: channel, message: message, chat_jid: chat, external_id: Waha::Anchoring.stanza_of(source_id),
      provider_id: source_id, direction: message.incoming? ? :incoming : :outgoing,
      event_type: legacy_anchor ? :edit : :message, anchor_message: anchor
    )
    message
  end

  # Loads one of the anonymized GOWS `message` payloads in
  # spec/fixtures/waha/gows. Merges are applied on top so a scenario can move a
  # fixture into a group chat or drop a field without editing the capture.
  def gows_payload(name, overrides = {})
    payload = JSON.parse(Rails.root.join("spec/fixtures/waha/gows/#{name}.json").read)
    payload.merge(overrides.deep_stringify_keys)
  end

  def gows_event(name, overrides = {})
    event = JSON.parse(Rails.root.join("spec/fixtures/waha/gows/#{name}.json").read)
    event.merge(overrides.deep_stringify_keys)
  end
end
