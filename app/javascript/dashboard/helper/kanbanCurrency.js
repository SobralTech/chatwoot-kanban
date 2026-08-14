// Constructing an Intl formatter is expensive, so the board shares a single one.
const formatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

export const formatCurrency = value => formatter.format(Number(value) || 0);
