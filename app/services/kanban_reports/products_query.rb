class KanbanReports::ProductsQuery < KanbanReports::BaseQuery
  def call
    won_card_ids = card_ids_for_events(unique_won_events)
    rows = KanbanCardProduct
           .where(account_id: account.id, kanban_card_id: won_card_ids)
           .group(:sku, :name)
           .pluck(
             :sku,
             :name,
             Arel.sql('SUM(quantity)'),
             Arel.sql('SUM(unit_price * quantity)'),
             Arel.sql('COUNT(DISTINCT kanban_card_id)')
           )
           .map { |sku, name, quantity, revenue, cards_count| product_row(sku, name, quantity, revenue, cards_count) }

    rows.sort_by { |row| [-row[:revenue].to_d, row[:product_name].to_s] }
  end

  private

  def unique_won_events
    unique_terminal_events.select { |event| event.event_type == 'won' }
  end

  def product_row(sku, name, quantity, revenue, cards_count)
    {
      sku: sku,
      product_name: name,
      quantity: quantity,
      revenue: KanbanCards::Totals.decimal_string(revenue),
      cards_count: cards_count
    }
  end
end
