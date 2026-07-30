# == Schema Information
#
# Table name: kanban_card_field_values
#
#  id                     :bigint           not null, primary key
#  value                  :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  kanban_card_id         :bigint           not null
#  kanban_custom_field_id :bigint           not null
#
# Indexes
#
#  index_kanban_card_field_values_on_account_id              (account_id)
#  index_kanban_card_field_values_on_card_and_field          (kanban_card_id,kanban_custom_field_id) UNIQUE
#  index_kanban_card_field_values_on_kanban_card_id          (kanban_card_id)
#  index_kanban_card_field_values_on_kanban_custom_field_id  (kanban_custom_field_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_card_id => kanban_cards.id)
#  fk_rails_...  (kanban_custom_field_id => kanban_custom_fields.id)
#
class KanbanCardFieldValue < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_card
  belongs_to :kanban_custom_field

  validates :kanban_custom_field_id, uniqueness: { scope: :kanban_card_id }
  validate :validate_account_consistency
  validate :validate_board_consistency
  validate :validate_value_matches_field_type

  private

  def validate_account_consistency
    return if kanban_card.blank? || account_id == kanban_card.account_id

    errors.add(:account_id, :invalid)
  end

  def validate_board_consistency
    return if kanban_card.blank? || kanban_custom_field.blank?
    return if kanban_custom_field.kanban_board_id == kanban_card.kanban_board_id

    errors.add(:kanban_custom_field, :invalid)
  end

  def validate_value_matches_field_type
    return if kanban_custom_field.blank?

    values = Array(value)

    if !kanban_custom_field.multiple? && values.size > 1
      errors.add(:value, I18n.t('errors.kanban_card_field_value.value.multiple_not_allowed', field_key: kanban_custom_field.key))
      return
    end

    return if values.all? { |item| valid_value_for_field_type?(item) }

    errors.add(:value, I18n.t(
                         'errors.kanban_card_field_value.value.invalid_for_field_type',
                         field_key: kanban_custom_field.key,
                         field_type: kanban_custom_field.field_type
                       ))
  end

  def valid_value_for_field_type?(item)
    case kanban_custom_field.field_type
    when 'number'
      item.is_a?(Numeric) || item.to_s.match?(/\A-?\d+(\.\d+)?\z/)
    when 'date'
      Date.iso8601(item.to_s)
      true
    when 'boolean'
      [true, false].include?(item)
    else
      true
    end
  rescue ArgumentError, TypeError
    false
  end
end
