# The only reader of the retired message correlation. Run synchronously during
# contract deployment with old workers stopped; it remains repeatable for audits.
class Migration::BackfillWahaMessageMappingsJob < ApplicationJob
  queue_as :async_database_migration

  STANZA_SQL = "regexp_replace(regexp_replace(messages.source_id, '_[^_]*@[^_]*$', ''), '^.*_', '')".freeze

  def perform(channel_id: nil)
    @stats = { checked: 0, backfilled: 0, skipped_ambiguous: 0, skipped_conflict: 0, ambiguities: [] }
    channels = channel_id ? Channel::Waha.where(id: channel_id) : Channel::Waha.all
    channels.find_each { |channel| backfill_channel(channel) }
    Rails.logger.info "[WAHA] mapping backfill complete: #{@stats}"
    @stats
  end

  private

  def backfill_channel(channel)
    messages = channel.inbox.messages.where(message_type: %i[incoming outgoing]).where.not(source_id: [nil, ''])
    messages.find_each { |message| backfill_message(channel, message) }
    channel.message_mappings.find_each { |mapping| fill_provider_id(mapping) }
    channel.delivery_attempts.find_each do |attempt|
      backfill_attempt(attempt)
      backfill_sent_parts(channel, attempt)
    end
    channel.message_mappings.where(event_type: :edit).find_each { |mapping| link_edit(channel, mapping) }
  end

  def backfill_message(channel, message)
    @stats[:checked] += 1
    chat = message.conversation.contact_inbox&.source_id
    stanza = Waha::Anchoring.stanza_of(message.source_id)
    return report(message, 'unresolvable chat or stanza') if chat.blank? || stanza.blank?

    return report(message, 'provider chat disagrees with conversation') if chat_mismatch?(channel, message, chat)

    event = message.additional_attributes['edit_of'].present? ? :edit : :message
    persist_legacy_identity(channel, message, chat, stanza, event)
  end

  def chat_mismatch?(channel, message, chat)
    return false if message.waha_message_mappings.exists?

    embedded_chat = Waha::Anchoring.chat_jid_of(message.source_id)
    embedded_chat.present? && Waha::Anchoring.chat_jids(channel, chat).exclude?(Waha::Jid.phone_jid(embedded_chat) || embedded_chat)
  end

  def persist_legacy_identity(channel, message, chat, stanza, event)
    scope = channel.message_mappings.where(chat_jid: chat, external_id: stanza, event_type: event)
    existing = scope.first
    collision = conflicting_messages(channel, message, chat, stanza, event).exists? || (existing && existing.message_id != message.id)
    if collision
      mapping = existing || create_mapping(channel, message, chat, stanza, event)
      mapping.update!(ambiguous: true)
      return report(message, 'multiple legacy messages claim this identity', conflict: true)
    end

    create_mapping(channel, message, chat, stanza, event) unless existing
  end

  def conflicting_messages(channel, message, chat, stanza, event)
    channel.inbox.messages.joins(conversation: :contact_inbox)
           .where(contact_inboxes: { source_id: Waha::Anchoring.chat_jids(channel, chat) })
           .where("#{STANZA_SQL} = ?", stanza)
           .where("(NULLIF(messages.additional_attributes->>'edit_of', '') IS NOT NULL) = ?", event == :edit)
           .where.not(id: message.id)
  end

  def create_mapping(channel, message, chat, stanza, event)
    mapping = WahaMessageMapping.create_canonical!(
      channel: channel, message: message, chat_jid: chat, external_id: stanza,
      direction: message.incoming? ? :incoming : :outgoing, event_type: event,
      provider_id: message.source_id, participant_jid: message.content_attributes['participant_jid']
    )
    @stats[:backfilled] += 1
    mapping
  end

  def fill_provider_id(mapping)
    return if mapping.provider_id.present?

    part = mapping.message.waha_delivery_attempt&.delivery_parts&.find_by(position: mapping.part)
    provider_id = part&.source_id.presence
    provider_id ||= matching_legacy_provider_id(mapping)
    provider_id ||= [mapping.outgoing?, mapping.chat_jid, mapping.external_id, mapping.participant_jid].compact.join('_')
    mapping.update!(provider_id: provider_id)
  end

  def matching_legacy_provider_id(mapping)
    return mapping.message.source_id if mapping.call?

    mapping.message.source_id if Waha::Anchoring.stanza_of(mapping.message.source_id) == mapping.external_id
  end

  def link_edit(channel, mapping)
    return if mapping.anchor_message_id.present? || mapping.ambiguous?

    legacy_anchor = mapping.message.additional_attributes['edit_of']
    anchor = Waha::Anchoring.find_message(channel, legacy_anchor, mapping.chat_jid)
    if anchor.nil?
      mapping.update!(ambiguous: true)
      return report(mapping.message, 'edit anchor missing or ambiguous')
    end

    mapping.update!(anchor_message: anchor)
  end

  def backfill_attempt(attempt)
    return if attempt.delivery_parts.exists?
    return if !attempt.sent? && attempt.dispatched_at.nil?

    attempt.with_lock do
      create_legacy_part(attempt) unless attempt.delivery_parts.exists?
    end
  end

  def create_legacy_part(attempt)
    if attempt.sending? && attempt.client_message_id.blank?
      report(attempt.message, 'dispatched attempt has no correlation ID; requires reconciliation')
    end

    attachment = attempt.message.attachments.order(:id).first
    attempt.delivery_parts.create!(
      position: 0, part_type: attachment ? :attachment : :text, attachment: attachment,
      status: attempt.sent? ? :sent : :pending, client_message_id: attempt.client_message_id,
      external_id: attempt.external_id, dispatched_at: attempt.dispatched_at,
      confirmed_at: (attempt.updated_at if attempt.sent?)
    )
  end

  def backfill_sent_parts(channel, attempt)
    attempt.delivery_parts.sent.find_each do |part|
      next if part.external_id.blank?

      mapping = channel.message_mappings.find_by(chat_jid: attempt.chat_jid, external_id: part.external_id, event_type: :message)
      if mapping
        if mapping.message_id != attempt.message_id
          mapping.update!(ambiguous: true)
          report(attempt.message, 'confirmed part conflicts with another message', conflict: true)
        end
        next
      end

      WahaMessageMapping.create_canonical!(
        channel: channel, message: attempt.message, chat_jid: attempt.chat_jid, external_id: part.external_id,
        direction: :outgoing, part: part.position, provider_id: part.source_id.presence
      )
      @stats[:backfilled] += 1
    end
  end

  def report(message, reason, conflict: false)
    @stats[conflict ? :skipped_conflict : :skipped_ambiguous] += 1
    @stats[:ambiguities] << { message_id: message.id, inbox_id: message.inbox_id, reason: reason }
    Rails.logger.warn "[WAHA] mapping backfill skipped message=#{message.id} inbox=#{message.inbox_id}: #{reason}"
  end
end
