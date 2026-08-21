// The bulk endpoints answer with the cards they could and could not touch, and answer
// with nothing at all when every card went through. Reading the body instead of the
// request is what lets a partial move be reported the same way everywhere.
export const bulkPartialMessage = (data, t) => {
  const failed = data?.failed || [];
  if (!failed.length) return null;

  const succeeded = data?.succeeded || [];

  return t('KANBAN.BULK.PARTIAL', {
    succeeded: succeeded.length,
    total: succeeded.length + failed.length,
    failed: failed.length,
  });
};
