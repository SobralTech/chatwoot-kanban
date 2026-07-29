# == Schema Information
#
# Table name: kanban_card_products
#
#  id             :bigint           not null, primary key
#  brand          :string
#  image_url      :string
#  name           :string           not null
#  position       :integer          default(0), not null
#  price_list     :string
#  price_type     :integer          default("pix"), not null
#  quantity       :integer          default(1), not null
#  sku            :string           not null
#  unit_price     :decimal(12, 2)   not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  kanban_card_id :bigint           not null
#
# Indexes
#
#  index_kanban_card_products_on_account_id      (account_id)
#  index_kanban_card_products_on_kanban_card_id  (kanban_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kanban_card_id => kanban_cards.id)
#
class KanbanCardProduct < ApplicationRecord
  belongs_to :account
  belongs_to :kanban_card

  enum :price_type, { pix: 0, base: 1 }

  validates :sku, presence: true
  validates :name, presence: true
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :validate_account_consistency

  scope :ordered, -> { order(position: :asc, id: :asc) }

  def subtotal
    unit_price * quantity
  end

  private

  def validate_account_consistency
    return if kanban_card.blank? || account_id == kanban_card.account_id

    errors.add(:account_id, :invalid)
  end
end
