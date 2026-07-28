const SNAPSHOT_PREFIX = 'kanban::board-state';
const SNAPSHOT_TTL = 30 * 60 * 1000;

const snapshotKey = (accountId, boardId) =>
  `${SNAPSHOT_PREFIX}::${accountId}::${boardId}`;

export const saveKanbanBoardSnapshot = ({ accountId, boardId, snapshot }) => {
  sessionStorage.setItem(
    snapshotKey(accountId, boardId),
    JSON.stringify({
      ...snapshot,
      boardId: Number(boardId),
      savedAt: Date.now(),
    })
  );
};

export const getKanbanBoardSnapshot = ({ accountId, boardId }) => {
  const key = snapshotKey(accountId, boardId);
  const value = sessionStorage.getItem(key);
  if (!value) return null;

  try {
    const snapshot = JSON.parse(value);
    const isExpired = Date.now() - snapshot.savedAt > SNAPSHOT_TTL;
    const isDifferentBoard = snapshot.boardId !== Number(boardId);

    if (isExpired || isDifferentBoard) {
      sessionStorage.removeItem(key);
      return null;
    }

    return snapshot;
  } catch {
    sessionStorage.removeItem(key);
    return null;
  }
};

export const removeKanbanBoardSnapshot = ({ accountId, boardId }) => {
  sessionStorage.removeItem(snapshotKey(accountId, boardId));
};
