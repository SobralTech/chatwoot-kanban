export const DISCOUNT_PERCENT = 'percent';
export const DISCOUNT_AMOUNT = 'amount';

// The client mirror of KanbanCard#discount_value, so the footer can price a
// discount while the user is still typing it. A percentage is relative to the
// items, an amount is already absolute.
export const discountValue = ({ itemsTotal, discountType, discountAmount }) => {
  const amount = Number(discountAmount);

  if (!Number.isFinite(amount) || amount <= 0) return 0;

  return discountType === DISCOUNT_PERCENT
    ? itemsTotal * (amount / 100)
    : amount;
};

// Mirrors KanbanCard#total_value: a discount can never push a card below zero.
export const cardTotal = discount =>
  Math.max(discount.itemsTotal - discountValue(discount), 0);

export const itemsTotalOf = products =>
  products.reduce(
    (sum, product) =>
      sum + Number(product.subtotal ?? product.unitPrice * product.quantity),
    0
  );
