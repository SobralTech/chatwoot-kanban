# Plain text (WAHA `chat`/no declared media). Unchanged from the pre-registry
# behavior: the body, resolved through @mentions.
class Waha::MessageConverters::Text < Waha::MessageConverters::Base
  pattr_initialize [:channel!, :payload!]

  def content
    Waha::MentionResolver.new(channel: channel, payload: payload).resolve(payload['body'].presence)
  end
end
