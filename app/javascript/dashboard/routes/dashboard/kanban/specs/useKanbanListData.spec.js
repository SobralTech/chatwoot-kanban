import { ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useKanbanListData } from 'dashboard/composables/useKanbanListData';

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: { showBoard: vi.fn(), getStageCards: vi.fn() },
}));

const boardResponse = () => ({
  data: {
    id: 3,
    name: 'Sales',
    stages: [
      {
        id: 7,
        name: 'Qualifying',
        color: '#111111',
        cards: [{ id: 1, subject: 'Renewal', card_priority: 'high' }],
        pagination: {
          total_count: 3,
          total_value: '250.0',
          next_cursor: { after_id: 1 },
        },
      },
      {
        id: 9,
        name: 'Won',
        color: '#222222',
        cards: [],
        pagination: { total_count: 0, total_value: '0.0', next_cursor: null },
      },
    ],
  },
});

const buildListData = () => {
  const board = ref(null);

  return {
    board,
    ...useKanbanListData({
      board,
      boardId: ref(3),
      currentFilterParams: () => ({ priorities: ['high'] }),
      isLoading: ref(false),
    }),
  };
};

describe('useKanbanListData', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    KanbanBoardsAPI.showBoard.mockResolvedValue(boardResponse());
  });

  it('cuts the board payload into one group per stage, with its count and value total', async () => {
    const { fetchList, groups } = buildListData();

    await fetchList();

    expect(KanbanBoardsAPI.showBoard).toHaveBeenCalledWith(3, {
      params: { priorities: ['high'] },
    });
    expect(groups.value).toMatchObject([
      {
        key: '7',
        stageId: 7,
        name: 'Qualifying',
        cardsCount: 3,
        totalValue: '250.0',
        hasMore: true,
      },
      { key: '9', stageId: 9, name: 'Won', cardsCount: 0, hasMore: false },
    ]);
    expect(groups.value[0].cards).toMatchObject([
      { id: 1, subject: 'Renewal', cardPriority: 'high' },
    ]);
  });

  it('pages a single group from its own cursor and leaves the others untouched', async () => {
    const { fetchList, groups, loadMoreForGroup } = buildListData();
    await fetchList();

    KanbanBoardsAPI.getStageCards.mockResolvedValue({
      data: {
        cards: [{ id: 2, subject: 'Upgrade' }],
        pagination: { next_cursor: null },
      },
    });

    await loadMoreForGroup('7');

    expect(KanbanBoardsAPI.showBoard).toHaveBeenCalledTimes(1);
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(3, 7, {
      limit: 20,
      cursor: { after_id: 1 },
      priorities: ['high'],
    });
    expect(groups.value[0].cards.map(card => card.id)).toEqual([1, 2]);
    expect(groups.value[0].hasMore).toBe(false);
    expect(groups.value[1].cards).toEqual([]);
  });

  it('does not page a group that has no cursor left', async () => {
    const { fetchList, loadMoreForGroup } = buildListData();
    await fetchList();

    await loadMoreForGroup('9');

    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });
});
