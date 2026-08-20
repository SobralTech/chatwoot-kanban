# Every card total on a board is the same pair: how many cards, and how much their
# products are worth. The stage columns and the funnel summary both read it, so the
# expressions and the wire format live here instead of once per query.
class KanbanCards::Totals
  Metric = Data.define(:count, :value)

  class << self
    # The whole scope as a single metric.
    def metric(scope)
      metrics(scope, all: nil).fetch(:all)
    end

    # One scan answers every metric: a FILTER narrows each aggregate to its own slice
    # of the same join, so asking for more metrics never costs more round trips. A
    # condition matching nothing - `IN ()` compiles to `1=0` - comes back as a zero
    # metric, which is how a board without a won or lost stage reports one.
    def metrics(scope, conditions)
      row = scope
            .left_outer_joins(:kanban_card_products)
            .pick(*conditions.values.flat_map { |condition| expressions(condition) })

      conditions.keys.each_with_index.to_h do |key, index|
        [key, Metric.new(row[index * 2].to_i, decimal_string(row[(index * 2) + 1]))]
      end
    end

    private

    def expressions(condition)
      [
        filtered(KanbanCard.arel_table[:id].count(true), condition),
        value_expression(condition)
      ]
    end

    def value_expression(condition)
      products = KanbanCardProduct.arel_table
      sum = named_function('SUM', products[:unit_price] * products[:quantity])

      named_function('COALESCE', filtered(sum, condition), Arel::Nodes.build_quoted(0))
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
