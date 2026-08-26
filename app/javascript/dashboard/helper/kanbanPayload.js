import camelcaseKeys from 'camelcase-keys';

// The kanban endpoints answer in snake_case, and every component that holds a card
// wants it camelized once at the edge so the wire's casing never reaches a template.
// A record either arrives wrapped in `payload` or is the body itself, depending on the
// endpoint, so unwrapping lives here instead of once per caller.
export const normalize = value => camelcaseKeys(value || {}, { deep: true });

export const normalizeCard = response =>
  normalize(response?.data?.payload ?? response?.data);

export const normalizeCollection = response =>
  normalize(response?.data?.payload ?? response?.data ?? []);
