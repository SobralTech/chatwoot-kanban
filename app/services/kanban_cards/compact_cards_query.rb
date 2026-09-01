class KanbanCards::CompactCardsQuery
  CARD_COLUMNS = %i[
    id account_id kanban_board_id kanban_stage_id previous_stage_id position origin subject active
    kanban_reason_id due_at stage_entered_at contact_id inbox_id conversation_id priority discount_type discount_amount
  ].freeze

  def self.call(ids)
    return [] if ids.blank?

    cards_by_id = KanbanCard
                  .select(*CARD_COLUMNS)
                  .where(id: ids)
                  .includes(
                    conversation: { assignee: { avatar_attachment: :blob } },
                    contact: { avatar_attachment: :blob },
                    inbox: [:channel, { avatar_attachment: :blob }],
                    labels: [],
                    kanban_card_products: [],
                    assignees: { avatar_attachment: :blob },
                    kanban_card_field_values: :kanban_custom_field
                  ).index_by(&:id)

    ids.filter_map { |id| cards_by_id[id] }
  end
end
