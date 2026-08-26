import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

// The board knows the conversation before it navigates, but the sidebar's kanban
// section only mounts once the conversation itself resolves. Firing the request
// here takes that round trip off the critical path; the section picks the answer
// up when it mounts.
let pendingPrefetch = null;

export const prefetchConversationCards = conversationId => {
  if (!conversationId) return;

  pendingPrefetch = {
    conversationId: String(conversationId),
    request: KanbanBoardsAPI.getConversationCards(conversationId).catch(
      () => null
    ),
  };
};

export const takePrefetchedConversationCards = conversationId => {
  if (pendingPrefetch?.conversationId !== String(conversationId)) return null;

  const { request } = pendingPrefetch;
  pendingPrefetch = null;
  return request;
};
