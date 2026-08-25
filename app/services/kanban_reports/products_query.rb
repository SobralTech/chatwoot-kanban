class KanbanReports::ProductsQuery < KanbanReports::BaseQuery
  def call
    won_card_ids = card_ids_for_events(unique_won_events)
    products = KanbanCardProduct.where(account_id: account.id, kanban_card_id: won_card_ids)
    rows = products.to_a.group_by { |product| [product.sku, product.name] }
    rows = rows.map { |(sku, name), product_rows| product_row(sku, name, product_rows) }

    rows.sort_by { |row| [-row[:revenue].to_d, row[:product_name].to_s] }
  end

  private

  def unique_won_events
    unique_terminal_events.select { |event| event.event_type == 'won' }
  end

  def product_row(sku, name, products)
    {
      sku: sku,
      product_name: name,
      quantity: products.sum(&:quantity),
      revenue: KanbanCards::Totals.decimal_string(products.sum(&:subtotal)),
      cards_count: products.map(&:kanban_card_id).uniq.length
    }
  end
end
