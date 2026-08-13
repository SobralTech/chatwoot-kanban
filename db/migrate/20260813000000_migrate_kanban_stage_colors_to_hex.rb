class MigrateKanbanStageColorsToHex < ActiveRecord::Migration[7.1]
  LEGACY_COLORS = {
    'slate' => '#8B8D98',
    'blue' => '#2781F6',
    'teal' => '#12A594',
    'green' => '#22C55E',
    'amber' => '#FFC53D',
    'orange' => '#F97316',
    'ruby' => '#E54666',
    'rose' => '#F43F5E',
    'violet' => '#6E56CF',
    'iris' => '#5B5BD6'
  }.freeze

  def up
    LEGACY_COLORS.each do |legacy_color, hex_color|
      execute <<~SQL.squish
        UPDATE kanban_stages
        SET color = #{quote(hex_color)}
        WHERE color = #{quote(legacy_color)}
      SQL
    end

    change_column_default :kanban_stages, :color, from: 'slate', to: '#8B8D98'
  end

  def down
    change_column_default :kanban_stages, :color, from: '#8B8D98', to: 'slate'
  end
end
