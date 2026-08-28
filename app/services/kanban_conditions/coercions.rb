# Comparing a stored condition value against a live attribute is the same problem for
# cards and for conversations: the stored side is always a string out of jsonb, while the
# live side may be an integer, a boolean, nil, or a list. Both matchers extend this so the
# two engines cannot drift on what "equal" means.
#
# `numeric:` is passed in rather than inferred, because each matcher knows which of its own
# attributes are ids and which are free text.
module KanbanConditions::Coercions
  def equal_to?(value, expected, numeric:)
    return value.any? { |item| scalar_equal?(item, expected, numeric: numeric) } if value.is_a?(Array)

    scalar_equal?(value, expected, numeric: numeric)
  end

  def scalar_equal?(value, expected, numeric:)
    return false if value.nil? || expected.nil?

    if boolean_value?(value) || boolean_value?(expected)
      ActiveModel::Type::Boolean.new.cast(value) == ActiveModel::Type::Boolean.new.cast(expected)
    elsif numeric
      numeric_compare(value, expected, :==)
    else
      value.to_s == expected.to_s
    end
  end

  def includes?(value, expected_values, numeric:)
    return expected_values.any? { |expected| value.to_s.include?(expected.to_s) } unless value.is_a?(Array)

    expected_values.any? { |expected| value.any? { |item| scalar_equal?(item, expected, numeric: numeric) } }
  end

  # Ordering only means something between two numbers: a blank total, or a value typed as
  # text, is a condition that does not match rather than an exception.
  def numeric_compare(value, expected, operator)
    left = numeric_value(value)
    right = numeric_value(expected)
    return false if left.nil? || right.nil?

    left.public_send(operator, right)
  end

  def numeric_value(value)
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def boolean_value?(value)
    value == true || value == false || %w[true false].include?(value.to_s.downcase)
  end
end
