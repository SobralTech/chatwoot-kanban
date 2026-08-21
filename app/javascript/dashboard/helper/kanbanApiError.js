// The kanban endpoints answer a failure in one of three shapes: `errors` from a
// rejected record (a list, a string, or a field => messages map depending on the
// validation), `error` from a controller that refused the request outright, and
// `message` from everything else. Callers only ever want one sentence to show, so
// the unwrapping lives here instead of once per component.
export const apiErrorMessage = (error, fallback) => {
  const data = error?.response?.data;
  const errors = data?.errors;

  if (Array.isArray(errors)) return errors.join(', ');
  if (typeof errors === 'string') return errors;
  if (errors && typeof errors === 'object') {
    return Object.values(errors).flat().join(', ');
  }

  return data?.error || data?.message || error?.message || fallback;
};
