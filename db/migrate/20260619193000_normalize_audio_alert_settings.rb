class NormalizeAudioAlertSettings < ActiveRecord::Migration[7.0]
  NORMALIZED_AUDIO_ALERTS_SQL = <<~SQL.squish.freeze
    UPDATE users
    SET ui_settings = jsonb_set(
      COALESCE(ui_settings, '{}'::jsonb),
      '{enable_audio_alerts}',
      to_jsonb(
        CASE COALESCE(ui_settings->>'enable_audio_alerts', '')
        WHEN '' THEN 'none'
        WHEN 'none' THEN 'none'
        WHEN 'false' THEN 'none'
        WHEN 'contact_message' THEN 'contact_message'
        WHEN 'conversation_mention' THEN 'conversation_mention'
        WHEN 'contact_message+conversation_mention' THEN 'contact_message+conversation_mention'
        WHEN 'conversation_mention+contact_message' THEN 'contact_message+conversation_mention'
        ELSE 'contact_message'
        END
      ),
      true
    )
    WHERE ui_settings ? 'enable_audio_alerts'
  SQL

  def up
    execute NORMALIZED_AUDIO_ALERTS_SQL
  end

  def down; end
end
