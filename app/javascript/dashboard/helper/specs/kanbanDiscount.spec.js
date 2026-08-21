import {
  DISCOUNT_AMOUNT,
  DISCOUNT_PERCENT,
  cardTotal,
  discountValue,
  itemsTotalOf,
} from 'dashboard/helper/kanbanDiscount';

describe('kanbanDiscount', () => {
  describe('itemsTotalOf', () => {
    it('prefers the server subtotal and falls back to price times quantity', () => {
      expect(
        itemsTotalOf([
          { subtotal: 200, unitPrice: 1, quantity: 1 },
          { unitPrice: 50, quantity: 2 },
        ])
      ).toBe(300);
    });

    it('is zero without items', () => {
      expect(itemsTotalOf([])).toBe(0);
    });
  });

  describe('discountValue', () => {
    it('reads a percentage against the items total', () => {
      expect(
        discountValue({
          itemsTotal: 200,
          discountType: DISCOUNT_PERCENT,
          discountAmount: 10,
        })
      ).toBe(20);
    });

    it('takes an amount as given', () => {
      expect(
        discountValue({
          itemsTotal: 200,
          discountType: DISCOUNT_AMOUNT,
          discountAmount: 30,
        })
      ).toBe(30);
    });

    it.each([null, '', undefined, 'abc', -5, 0])(
      'is zero for a discount of %o',
      discountAmount => {
        expect(
          discountValue({
            itemsTotal: 200,
            discountType: DISCOUNT_PERCENT,
            discountAmount,
          })
        ).toBe(0);
      }
    );
  });

  describe('cardTotal', () => {
    it('subtracts the discount from the items total', () => {
      expect(
        cardTotal({
          itemsTotal: 200,
          discountType: DISCOUNT_PERCENT,
          discountAmount: 10,
        })
      ).toBe(180);
    });

    it('floors at zero when the discount exceeds the items total', () => {
      expect(
        cardTotal({
          itemsTotal: 200,
          discountType: DISCOUNT_AMOUNT,
          discountAmount: 250,
        })
      ).toBe(0);
    });
  });
});
