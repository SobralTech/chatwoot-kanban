class Waha::OutgoingMentionParser
  ALL_PATTERN = /(^|\s)@all(?![\w@])/i
  LID_PATTERN = /(^|\s)@(\d+)@lid(?![\w@])/i
  PHONE_PATTERN = /(^|\s)@(\d{7,15})(?![\w@])/i

  attr_reader :mentions, :text

  def initialize(text:, chat_id:)
    @source_text = text.to_s
    @text = @source_text.dup
    @mentions = []

    parse if Waha::Jid.group?(chat_id)
  end

  def payload
    mentions.empty? ? {} : { mentions: mentions }
  end

  private

  def parse
    parse_all
    parse_lids
    parse_phones
    @mentions.uniq!
  end

  def parse_all
    return unless @source_text.match?(ALL_PATTERN)

    mentions << 'all'
    @text = text.gsub(ALL_PATTERN, '\\1').strip
    @text = ' ' if text.blank?
  end

  def parse_lids
    @source_text.scan(LID_PATTERN) { |_, digits| mentions << "#{digits}@lid" }
    @text = text.gsub(LID_PATTERN, '\\1@\\2')
  end

  def parse_phones
    @source_text.scan(PHONE_PATTERN) { |_, digits| mentions << "#{digits}@c.us" }
  end
end
