class Migration::BackfillWahaMessageMappingsJob < ApplicationJob
  queue_as :async_database_migration

  # Fills the new canonical mapping (ticket 07) from messages that already carry
  # the legacy source_id correlation. Only unambiguous rows are backfilled: a
  # missing stanza, an unresolvable chat, or a collision with an existing row
  # (caught by the DB's unique constraint) is reported and left alone rather
  # than associated by guessing.
  def perform(channel_id: nil)
    stats = { checked: 0, backfilled: 0, skipped_ambiguous: 0, skipped_conflict: 0 }
    channels(channel_id).find_each { |channel| backfill_channel(channel, stats) }
    Rails.logger.info "[WAHA] mapping backfill complete: #{stats}"
    stats
  end

  private

  def channels(channel_id)
    channel_id ? Channel::Waha.where(id: channel_id) : Channel::Waha.all
  end

  def backfill_channel(channel, stats)
    candidate_messages(channel).find_each do |message|
      stats[:checked] += 1
      backfill_message(channel, message, stats)
    end
  end

  def candidate_messages(channel)
    channel.inbox.messages.where(message_type: %i[incoming outgoing])
           .where.not(source_id: nil)
           .where.missing(:waha_message_mappings)
  end

  def backfill_message(channel, message, stats)
    chat_jid = message.conversation.contact_inbox&.source_id
    external_id = Waha::Anchoring.stanza_of(message.source_id)

    if chat_jid.blank? || external_id.blank?
      report_ambiguous(message, 'unresolvable chat or stanza')
      stats[:skipped_ambiguous] += 1
      return
    end

    create_mapping(channel, message, chat_jid, external_id, stats)
  end

  def create_mapping(channel, message, chat_jid, external_id, stats)
    WahaMessageMapping.create!(
      channel: channel,
      message: message,
      chat_jid: chat_jid,
      external_id: external_id,
      direction: message.incoming? ? :incoming : :outgoing,
      event_type: message.additional_attributes['edit_of'].present? ? :edit : :message,
      participant_jid: message.content_attributes['participant_jid']
    )
    stats[:backfilled] += 1
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    report_ambiguous(message, e.message)
    stats[:skipped_conflict] += 1
  end

  def report_ambiguous(message, reason)
    Rails.logger.warn "[WAHA] mapping backfill skipped message #{message.id} (source_id=#{message.source_id}): #{reason}"
  end
end
