# Every card total on a board is the same pair: how many cards, and how much their
# items are worth after the card discount. The stage columns and the funnel summary
# all read it, so the expressions and the wire format live here instead of once per
# query.
class KanbanCards::Totals
  Metric = Data.define(:count, :value)
  PRODUCT_TOTALS_ALIAS = 'kanban_card_product_totals'.freeze

  class << self
    # The whole scope as a single metric.
    def metric(scope)
      metrics(scope, all: nil).fetch(:all)
    end

    # One scan answers every metric: a FILTER narrows each aggregate to its own slice
    # of the same card-level relation, so asking for more metrics never costs more
    # round trips. A condition matching nothing - `IN ()` compiles to `1=0` - comes
    # back as a zero metric, which is how a board without a won or lost stage reports
    # one.
    def metrics(scope, conditions)
      row = totals_scope(scope).pick(*conditions.values.flat_map { |condition| expressions(condition) })

      conditions.keys.each_with_index.to_h do |key, index|
        [key, Metric.new(row[index * 2].to_i, decimal_string(row[(index * 2) + 1]))]
      end
    end

    private

    def totals_scope(scope)
      scope.joins(<<~SQL.squish)
        LEFT OUTER JOIN (#{product_totals.to_sql}) AS #{PRODUCT_TOTALS_ALIAS}
          ON #{PRODUCT_TOTALS_ALIAS}.kanban_card_id = kanban_cards.id
      SQL
    end

    def product_totals
      KanbanCardProduct
        .select(:kanban_card_id, Arel.sql('SUM(unit_price * quantity) AS items_total'))
        .group(:kanban_card_id)
    end

    def expressions(condition)
      [
        filtered(KanbanCard.arel_table[:id].count(true), condition),
        value_expression(condition)
      ]
    end

    def value_expression(condition)
      sum = named_function('SUM', Arel.sql(card_total_sql))

      named_function('COALESCE', filtered(sum, condition), Arel::Nodes.build_quoted(0))
    end

    def card_total_sql
      <<~SQL.squish
        GREATEST(
          COALESCE(#{PRODUCT_TOTALS_ALIAS}.items_total, 0) -
          CASE
            WHEN kanban_cards.discount_cents IS NOT NULL THEN kanban_cards.discount_cents / 100.0
            WHEN kanban_cards.discount_percent IS NOT NULL THEN
              COALESCE(#{PRODUCT_TOTALS_ALIAS}.items_total, 0) * kanban_cards.discount_percent / 100.0
            ELSE 0
          END,
          0
        )
      SQL
    end

    # A nil condition aggregates the whole scope, so the filter is left off entirely.
    def filtered(aggregate, condition)
      condition ? aggregate.filter(condition) : aggregate
    end

    def named_function(name, *expressions)
      Arel::Nodes::NamedFunction.new(name, expressions)
    end

    def decimal_string(value)
      BigDecimal(value.to_s).to_s('F')
    end
  end
end
