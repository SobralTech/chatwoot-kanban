# Applies a GOWS poll.vote event to the poll message it references. A vote is
# an update to an existing interactive message, never another poll message in
# the conversation. Its own canonical mapping makes WAHA webhook redelivery
# idempotent and lets a later vote from the same participant replace the
# observed selection.
class Waha::PollVoteApplier
  pattr_initialize [:channel!, :payload!]

  def perform
    return false unless valid_vote?

    target = poll_message
    return false if target&.content_attributes&.dig('poll').blank?

    apply_to_poll(target)
  rescue ActiveRecord::RecordNotUnique
    true
  end

  private

  def valid_vote?
    poll_source_id.present? && vote_id.present? && vote.key?('selectedOptions')
  end

  def apply_to_poll(target)
    Waha::Locking.with_chat_lock(channel, lock_chat_jids(target)) do
      target = poll_message
      next false if target&.content_attributes&.dig('poll').blank?

      target.with_lock { apply_locked(target) }
    end
  end

  def lock_chat_jids(target)
    [poll_chat_jid, target.conversation.contact_inbox&.source_id].compact
  end

  def apply_locked(target)
    return true if vote_mapping(target)

    votes = updated_votes(target)
    persist_vote(target, votes)
    true
  end

  def updated_votes(target)
    (target.content_attributes['poll_votes'] || {}).deep_dup.tap do |votes|
      votes[voter_key] = { 'selected_options' => selected_options, 'timestamp' => vote['timestamp'] }.compact
    end
  end

  def persist_vote(target, votes)
    content_attributes = target.content_attributes.merge('poll_votes' => votes)
    target.update!(
      content: Waha::MessageConverters::Poll.render(content_attributes['poll'], votes: votes),
      content_attributes: content_attributes
    )
    WahaMessageMapping.create_canonical!(
      channel: channel,
      message: target,
      chat_jid: canonical_chat_jid(target),
      external_id: Waha::Anchoring.stanza_of(vote_id),
      direction: vote['fromMe'] ? :outgoing : :incoming,
      event_type: :poll_vote,
      participant_jid: vote['participant'].presence || vote['from'].presence
    )
  end

  def poll
    @poll ||= payload['poll'] || {}
  end

  def vote
    @vote ||= payload['vote'] || {}
  end

  def poll_source_id
    poll['id']
  end

  def vote_id
    vote['id']
  end

  def poll_chat_jid
    @poll_chat_jid ||= Waha::Anchoring.chat_jid_of(poll_source_id) || poll['chatId'].presence || poll['to'].presence || poll['from'].presence
  end

  def poll_message
    Waha::Anchoring.find_message(channel, poll_source_id, poll_chat_jid)
  end

  def canonical_chat_jid(target)
    target.conversation.contact_inbox&.source_id || poll_chat_jid
  end

  def vote_mapping(target)
    WahaMessageMapping.find_mapping(
      channel: channel,
      chat_jid: canonical_chat_jid(target),
      external_id: Waha::Anchoring.stanza_of(vote_id),
      event_type: :poll_vote
    )
  end

  def selected_options
    Array(vote['selectedOptions']).filter_map(&:presence)
  end

  def voter_key
    vote['participant'].presence || vote['from'].presence || vote_id
  end
end
