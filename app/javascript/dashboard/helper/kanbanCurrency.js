// Constructing an Intl formatter is expensive, so the board shares a single one.
const formatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const compactFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  notation: 'compact',
  maximumFractionDigits: 1,
});

export const formatCurrency = value => formatter.format(Number(value) || 0);

export const formatCompactCurrency = value =>
  compactFormatter.format(Number(value) || 0);
