import camelcaseKeys from 'camelcase-keys';

export const normalizePayload = payload =>
  camelcaseKeys(payload || {}, { deep: true });
