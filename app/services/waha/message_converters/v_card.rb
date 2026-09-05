# One or more shared contacts. GOWS ships the raw whatsmeow proto under
# `_data.Message.contactMessage` (a single card) or
# `_data.Message.contactsArrayMessage.contacts` (several); WAHA also normalizes
# every engine's cards into the top-level `vCards` array.
#
# Chatwoot's native `contact` attachment renders only when it is the message's
# single attachment and shows exactly one phone number, so it would silently
# drop a contact's second number or an array's second contact. Every parsed
# name and phone goes into the message body instead, and each original card is
# attached as a downloadable .vcf, so nothing the payload carried is lost.
class Waha::MessageConverters::VCard < Waha::MessageConverters::Base
  CONTENT_TYPE = 'text/vcard'.freeze

  pattr_initialize [:vcards!]

  # Returns every non-blank card in the payload; an empty result sends the
  # registry to the visible fallback instead of an empty "shared contact".
  def self.extract(payload)
    cards = from_gows(payload) || payload['vCards']
    Array(cards).select { |vcard| vcard.is_a?(String) && vcard.present? }
  end

  def self.from_gows(payload)
    message = payload.dig('_data', 'Message')
    return nil unless message.is_a?(Hash)

    return [message.dig('contactMessage', 'vcard')] if message['contactMessage'].is_a?(Hash)

    contacts = message.dig('contactsArrayMessage', 'contacts')
    contacts.pluck('vcard') if contacts.is_a?(Array)
  end

  private_class_method :from_gows

  def content
    lines = [I18n.t('conversations.messages.waha_contacts.header', count: cards.size)]
    cards.each do |card|
      lines << I18n.t('conversations.messages.waha_contacts.name', name: card[:name])
      card[:phones].each { |phone| lines << I18n.t('conversations.messages.waha_contacts.phone', phone: phone) }
    end
    lines.join("\n")
  end

  def attach(message)
    vcards.each_with_index do |vcard, index|
      message.attachments.build(
        account_id: message.account_id,
        file_type: :file,
        file: { io: StringIO.new(vcard), filename: "contact-#{index + 1}.vcf", content_type: CONTENT_TYPE }
      )
    end
  end

  private

  def cards
    @cards ||= vcards.map { |vcard| parse(vcard) }
  end

  # WhatsApp shares vCard 3.0. Only the display name and the phone numbers are
  # read here; the untouched card travels as the attachment for everything else.
  def parse(vcard)
    lines = vcard.split(/\r?\n/).filter_map do |line|
      name, value = line.split(':', 2)
      [name.split(';').first.to_s.upcase, value.strip] if value.present?
    end
    properties = lines.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

    { name: name_of(properties), phones: Array(properties['TEL']).uniq }
  end

  # FN is the display name WhatsApp fills in; N ("Family;Given;...") is the only
  # name a card exported from another app may carry.
  def name_of(properties)
    properties['FN']&.first.presence || structured_name(properties) || I18n.t('conversations.messages.waha_contacts.unnamed')
  end

  def structured_name(properties)
    properties['N']&.first.to_s.split(';').map(&:strip).compact_blank.reverse.join(' ').presence
  end
end
