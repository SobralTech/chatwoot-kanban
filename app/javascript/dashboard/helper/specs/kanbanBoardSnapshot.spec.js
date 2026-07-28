import {
  getKanbanBoardSnapshot,
  removeKanbanBoardSnapshot,
  saveKanbanBoardSnapshot,
} from '../kanbanBoardSnapshot';

describe('kanbanBoardSnapshot', () => {
  beforeEach(() => {
    sessionStorage.clear();
    vi.spyOn(Date, 'now').mockReturnValue(1_000_000);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('stores snapshots independently by account and board', () => {
    saveKanbanBoardSnapshot({
      accountId: 1,
      boardId: 10,
      snapshot: { scrollLeft: 120 },
    });

    expect(getKanbanBoardSnapshot({ accountId: 1, boardId: 10 })).toEqual({
      scrollLeft: 120,
      savedAt: 1_000_000,
    });
    expect(getKanbanBoardSnapshot({ accountId: 1, boardId: 11 })).toBeNull();
  });

  it('discards snapshots older than 30 minutes', () => {
    saveKanbanBoardSnapshot({
      accountId: 1,
      boardId: 10,
      snapshot: { scrollLeft: 120 },
    });
    Date.now.mockReturnValue(1_000_000 + 30 * 60 * 1000 + 1);

    expect(getKanbanBoardSnapshot({ accountId: 1, boardId: 10 })).toBeNull();
  });

  it('removes a snapshot after it is applied', () => {
    saveKanbanBoardSnapshot({
      accountId: 1,
      boardId: 10,
      snapshot: { scrollLeft: 120 },
    });

    removeKanbanBoardSnapshot({ accountId: 1, boardId: 10 });

    expect(getKanbanBoardSnapshot({ accountId: 1, boardId: 10 })).toBeNull();
  });
});
