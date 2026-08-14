const DATE_ONLY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

// Due dates are edited as calendar days (YYYY-MM-DD) but stored as timestamps.
export const formatDateInput = value => {
  if (!value) return '';
  if (DATE_ONLY_PATTERN.test(value)) return value;

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';

  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  return `${date.getFullYear()}-${month}-${day}`;
};

// Midday keeps the stored timestamp on the picked day in either direction of UTC.
export const toIso8601 = value => {
  if (!value) return null;

  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day, 12).toISOString();
};
