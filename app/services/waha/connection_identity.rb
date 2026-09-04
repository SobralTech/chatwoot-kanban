require 'uri'

class Waha::ConnectionIdentity
  class << self
    def normalize_url(value)
      uri = URI.parse(value.to_s.strip)
      return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank? && uri.query.blank?

      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
      uri.fragment = nil
      uri.path = uri.path.to_s.sub(%r{/+\z}, '')
      uri.port = nil if default_port?(uri)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def normalize_session_name(value)
      value.to_s.strip.gsub(/[^a-zA-Z0-9._-]+/, '_').presence
    end

    private

    def default_port?(uri)
      (uri.scheme == 'http' && uri.port == 80) || (uri.scheme == 'https' && uri.port == 443)
    end
  end
end
