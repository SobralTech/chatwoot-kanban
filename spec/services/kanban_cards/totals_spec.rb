require 'rails_helper'

RSpec.describe KanbanCards::Totals do
  # The discount is computed twice: once per record in KanbanCard#total_value and
  # once as an aggregate in this service's SQL. They can only drift silently, so
  # every discount shape is checked against both.
  describe 'parity with KanbanCard#total_value' do
    let(:card) do
      create(:kanban_card).tap do |kanban_card|
        KanbanCardProduct.create!(
          account: kanban_card.account,
          kanban_card: kanban_card,
          sku: SecureRandom.hex(4),
          name: 'Product',
          unit_price: 100,
          quantity: 2
        )
      end
    end

    def aggregate_value
      described_class.metric(KanbanCard.where(id: card.id)).value
    end

    it 'agrees on a percentage discount' do
      card.update!(discount_type: :percent, discount_amount: 10)

      expect(card.reload.total_value).to eq(BigDecimal(180))
      expect(aggregate_value).to eq(card.total_value)
    end

    it 'agrees on an absolute discount' do
      card.update!(discount_type: :amount, discount_amount: 25)

      expect(card.reload.total_value).to eq(BigDecimal(175))
      expect(aggregate_value).to eq(card.total_value)
    end

    it 'agrees without a discount' do
      card.update!(discount_amount: nil)

      expect(card.reload.total_value).to eq(BigDecimal(200))
      expect(aggregate_value).to eq(card.total_value)
    end

    it 'agrees when the discount exceeds the items total' do
      card.update!(discount_type: :amount, discount_amount: 5000)

      expect(card.reload.total_value).to eq(BigDecimal(0))
      expect(aggregate_value).to eq(card.total_value)
    end

    it 'agrees for a card without any items' do
      empty_card = create(:kanban_card)

      expect(empty_card.total_value).to eq(BigDecimal(0))
      expect(described_class.metric(KanbanCard.where(id: empty_card.id)).value).to eq(BigDecimal(0))
    end
  end

  describe '.decimal_string' do
    it 'formats money as a plain decimal string' do
      expect(described_class.decimal_string(BigDecimal(430))).to eq('430.0')
    end

    it 'passes nil through so an absent total stays absent' do
      expect(described_class.decimal_string(nil)).to be_nil
    end
  end
end
