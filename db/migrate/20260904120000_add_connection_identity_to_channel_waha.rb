require 'uri'

# These writes are a one-time backfill which must preserve legacy duplicate rows.
# rubocop:disable Style/OneClassPerFile, Rails/SkipsModelValidations, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class AddConnectionIdentityToChannelWaha < ActiveRecord::Migration[7.1]
  class ChannelWaha < ActiveRecord::Base
    self.table_name = 'channel_waha'
  end

  def up
    add_column :channel_waha, :normalized_waha_url, :string
    add_column :channel_waha, :normalized_session_name, :string
    add_column :channel_waha, :connection_identity_conflict, :boolean, null: false, default: false

    backfill_connection_identities
    report_duplicate_connection_identities

    add_index :channel_waha, %i[normalized_waha_url normalized_session_name],
              unique: true,
              where: 'connection_identity_conflict = false',
              name: 'index_channel_waha_on_connection_identity'
  end

  def down
    remove_index :channel_waha, name: 'index_channel_waha_on_connection_identity'
    remove_column :channel_waha, :connection_identity_conflict
    remove_column :channel_waha, :normalized_session_name
    remove_column :channel_waha, :normalized_waha_url
  end

  private

  def backfill_connection_identities
    say_with_time 'Normalizing WAHA connection identities' do
      ChannelWaha.find_each do |channel|
        url = normalize_url(channel.waha_url)
        session_name = normalize_session_name(channel.session_name)
        conflict = url.blank? || session_name.blank?

        channel.update_columns(
          normalized_waha_url: url,
          normalized_session_name: session_name,
          connection_identity_conflict: conflict
        )
      end
    end
  end

  def report_duplicate_connection_identities
    duplicate_groups = ChannelWaha.where(connection_identity_conflict: false)
                                  .where('normalized_waha_url IS NOT NULL AND normalized_session_name IS NOT NULL')
                                  .group(:normalized_waha_url, :normalized_session_name)
                                  .having('COUNT(*) > 1')
                                  .pluck(:normalized_waha_url, :normalized_session_name)

    duplicate_groups.each do |url, session_name|
      channels = ChannelWaha.where(normalized_waha_url: url, normalized_session_name: session_name)
      channel_ids = channels.pluck(:id)
      channels.update_all(connection_identity_conflict: true)
      message = "[WAHA] Duplicate connection identity #{url} / #{session_name} on channels #{channel_ids.join(', ')}. " \
                'The channels were left untouched and are blocked until one is reconfigured.'
      say message
      Rails.logger.error(message)
    end
  end

  def normalize_url(value)
    uri = URI.parse(value.to_s.strip)
    return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank? && uri.query.blank?

    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.fragment = nil
    uri.path = uri.path.to_s.sub(%r{/+\z}, '')
    uri.port = nil if (uri.scheme == 'http' && uri.port == 80) || (uri.scheme == 'https' && uri.port == 443)
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def normalize_session_name(value)
    value.to_s.strip.gsub(/[^a-zA-Z0-9._-]+/, '_').presence
  end
end
# rubocop:enable Style/OneClassPerFile, Rails/SkipsModelValidations, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
