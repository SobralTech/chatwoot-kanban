# A reply that originated from a "click to WhatsApp" Facebook/Instagram ad.
# GOWS attaches this as `contextInfo.externalAdReply` on the extendedTextMessage
# WhatsApp opens with — the same message the contact's own typed greeting (or
# WhatsApp's default one) lives on. So this wraps whichever converter the
# registry already chose for that text, the same way StatusReply wraps a
# status reply's own content, and only adds the ad as metadata plus (when the
# contact's own message is blank) a synthesized visible summary — the contact's
# real words are never replaced by a synthesized card.
#
# Deliberately does not download the ad's image: `mediaURL`/`thumbnailURL` are
# third-party CDN URLs from an inbound payload, not WAHA-hosted media behind
# the channel's own API key, so fetching them here would be an open redirect
# for an SSRF probe. The URL is preserved as a link instead.
class Waha::MessageConverters::FacebookAd < Waha::MessageConverters::Base
  pattr_initialize [:inner!, :ad!]

  def self.extract(payload)
    node = ad_node(payload)
    return unless node.is_a?(Hash)

    title = node['title'].presence
    body = node['body'].presence
    return if title.blank? && body.blank?

    {
      title: title,
      body: body,
      media_url: node['mediaURL'].presence || node['thumbnailURL'].presence,
      source_url: node['sourceURL'].presence
    }.compact
  end

  def self.ad_node(payload)
    payload.dig('_data', 'Message', 'extendedTextMessage', 'contextInfo', 'externalAdReply')
  end
  private_class_method :ad_node

  def download
    inner.download
  end

  def content
    inner.content.presence || synthesized_content
  end

  def metadata
    base = inner.content.present? ? inner.metadata : inner.metadata.except(:is_unsupported)
    base.merge(facebook_ad: ad)
  end

  def attach(message)
    inner.attach(message)
  end

  def downloads_attachment?
    inner.downloads_attachment?
  end

  private

  def synthesized_content
    ([I18n.t('conversations.messages.waha_facebook_ad.header'), ad[:title], ad[:body], media_line, source_line]).compact_blank.join("\n")
  end

  def media_line
    I18n.t('conversations.messages.waha_facebook_ad.media', url: ad[:media_url]) if ad[:media_url]
  end

  def source_line
    I18n.t('conversations.messages.waha_facebook_ad.source', url: ad[:source_url]) if ad[:source_url]
  end
end
