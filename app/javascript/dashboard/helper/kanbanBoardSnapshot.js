import SessionStorage from 'shared/helpers/sessionStorage';
import { LocalStorage } from 'shared/helpers/localStorage';

const SNAPSHOT_PREFIX = 'kanban::board-state';
const SNAPSHOT_TTL = 30 * 60 * 1000;

const snapshotKey = (accountId, boardId) =>
  `${SNAPSHOT_PREFIX}::${accountId}::${boardId}`;

const prefsKey = (accountId, boardId, userId) =>
  `kanban_board_prefs_${accountId}_${boardId}_${userId}`;

export const saveKanbanBoardSnapshot = ({ accountId, boardId, snapshot }) => {
  SessionStorage.set(snapshotKey(accountId, boardId), {
    ...snapshot,
    savedAt: Date.now(),
  });
};

export const removeKanbanBoardSnapshot = ({ accountId, boardId }) => {
  SessionStorage.remove(snapshotKey(accountId, boardId));
};

export const getKanbanBoardSnapshot = ({ accountId, boardId }) => {
  const snapshot = SessionStorage.get(snapshotKey(accountId, boardId));
  if (!snapshot) return null;

  // A tab reloaded on the conversation route keeps its snapshot, so drop
  // stale ones instead of restoring a long-abandoned board layout.
  if (Date.now() - snapshot.savedAt > SNAPSHOT_TTL) {
    removeKanbanBoardSnapshot({ accountId, boardId });
    return null;
  }

  return snapshot;
};

export const saveKanbanBoardPrefs = ({ accountId, boardId, userId, prefs }) => {
  LocalStorage.set(prefsKey(accountId, boardId, userId), prefs);
};

export const getKanbanBoardPrefs = ({ accountId, boardId, userId }) => {
  return LocalStorage.get(prefsKey(accountId, boardId, userId));
};
