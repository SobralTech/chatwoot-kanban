class Waha::ReactionService < Waha::BaseMessageActionService
  pattr_initialize [:message!, :emoji!]

  # Pushes a reaction to WhatsApp. The business number has a single reaction
  # slot per message, so a new emoji replaces the previous one and an empty
  # string removes it. Like edits, the chip and the activity are applied
  # locally only when the message.reaction webhook round-trips back — no
  # optimistic UI. The PUT always targets the family anchor (the real WhatsApp
  # message), never an edit mirror.
  def perform
    # ReactionApplier consumes the marker to attribute the chip to this agent.
    stash_current_user('pending_reaction_agent_id')
    dispatch!(:put, 'reaction', { messageId: anchor_source_id, reaction: emoji, session: channel.session_name })
  end
end
