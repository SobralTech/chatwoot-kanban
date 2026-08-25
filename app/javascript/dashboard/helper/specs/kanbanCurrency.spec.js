import { formatCompactCurrency, formatCurrency } from '../kanbanCurrency';

// pt-BR currency output uses non-breaking spaces.
const BRL = (...parts) => parts.join(String.fromCharCode(160));

describe('kanbanCurrency', () => {
  it('formats the full value with two decimals', () => {
    expect(formatCurrency(456465465.56)).toBe(BRL('R$', '456.465.465,56'));
  });

  it('compacts large values to a single fraction digit', () => {
    expect(formatCompactCurrency(4800)).toBe(BRL('R$', '4,8', 'mil'));
    expect(formatCompactCurrency(12400)).toBe(BRL('R$', '12,4', 'mil'));
    expect(formatCompactCurrency(456465465.56)).toBe(BRL('R$', '456,5', 'mi'));
  });

  it('keeps one fraction digit for values under a thousand', () => {
    expect(formatCompactCurrency(125.5)).toBe(BRL('R$', '125,5'));
  });

  it('falls back to zero for empty input', () => {
    const zero = BRL('R$', '0');
    expect(formatCompactCurrency(0)).toBe(zero);
    expect(formatCompactCurrency(null)).toBe(zero);
    expect(formatCompactCurrency(undefined)).toBe(zero);
  });

  it('keeps the sign of negative values', () => {
    expect(formatCompactCurrency(-50)).toBe(BRL('-R$', '50'));
    expect(formatCompactCurrency(-12400)).toBe(BRL('-R$', '12,4', 'mil'));
  });
});
