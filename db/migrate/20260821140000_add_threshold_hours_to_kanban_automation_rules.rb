class AddThresholdHoursToKanbanAutomationRules < ActiveRecord::Migration[7.1]
  BACKFILL_SQL = <<~SQL.squish.freeze
    UPDATE kanban_automation_rules
    SET threshold_hours = sub.hours,
        conditions = sub.remaining
    FROM (
      SELECT r.id,
             (SELECT (c ->> 'values')::jsonb ->> 0
                FROM jsonb_array_elements(r.conditions) c
               WHERE c ->> 'attribute_key' = 'hours_in_stage'
               LIMIT 1)::numeric AS hours,
             COALESCE(
               (SELECT jsonb_agg(c)
                  FROM jsonb_array_elements(r.conditions) c
                 WHERE c ->> 'attribute_key' <> 'hours_in_stage'),
               '[]'::jsonb
             ) AS remaining
        FROM kanban_automation_rules r
       WHERE r.event_name IN ('card_stalled', 'due_soon', 'no_reply')
    ) sub
    WHERE kanban_automation_rules.id = sub.id
      AND sub.hours IS NOT NULL
  SQL

  def up
    add_column :kanban_automation_rules, :threshold_hours, :integer unless column_exists?(:kanban_automation_rules, :threshold_hours)

    backfill_from_conditions
  end

  def down
    remove_column :kanban_automation_rules, :threshold_hours
  end

  private

  # Time-based rules used to carry their threshold as a synthetic `hours_in_stage`
  # condition. Move it to the column and drop the condition, so the matcher stops
  # evaluating it as a real filter.
  def backfill_from_conditions
    execute(BACKFILL_SQL)
  end
end
