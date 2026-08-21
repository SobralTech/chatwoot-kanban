const boardAllowedInboxIds = board => {
  const allowedInboxIds =
    board?.allowedInboxIds ?? board?.allowed_inbox_ids ?? null;
  const allowedInboxes = board?.allowedInboxes ?? board?.allowed_inboxes;

  return (
    allowedInboxIds ??
    allowedInboxes?.map(allowedInbox => allowedInbox.id) ??
    []
  ).map(Number);
};

export const boardAcceptsInbox = (board, inboxId) => {
  if (!inboxId) return true;

  const inboxScopeMode = board?.inboxScopeMode ?? board?.inbox_scope_mode;

  return (
    inboxScopeMode !== 'selected_inboxes' ||
    boardAllowedInboxIds(board).includes(Number(inboxId))
  );
};
