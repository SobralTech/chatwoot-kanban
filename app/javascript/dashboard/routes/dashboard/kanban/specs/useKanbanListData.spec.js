import { ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useKanbanListData } from 'dashboard/composables/useKanbanListData';

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    showBoard: vi.fn(),
    getStageCards: vi.fn(),
    getBoardCards: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

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

// Ordered by assignee, the way the funnel endpoint answers: the cards with none
// first, then the ones whose first assignee by name is Ana.
const assigneeCardsResponse = () => ({
  data: {
    cards: [
      { id: 12, subject: 'Upsell', priority: null, assignees: [] },
      {
        id: 11,
        subject: 'Renewal',
        priority: 'high',
        assignees: [
          { id: 2, name: 'Bruna' },
          { id: 1, name: 'Ana' },
        ],
      },
    ],
    groups: [
      { key: 'unassigned', name: null, count: 3, total_value: '80.0' },
      { key: '1', name: 'Ana', count: 2, total_value: '150.0' },
    ],
    pagination: { next_cursor: { after_id: 11 }, total_count: 5 },
  },
});

const priorityCardsResponse = () => ({
  data: {
    cards: [
      { id: 12, subject: 'Upsell', priority: null, assignees: [] },
      { id: 11, subject: 'Renewal', priority: 'high', assignees: [] },
    ],
    groups: [
      { key: 'none', name: null, count: 1, total_value: '0.0' },
      { key: 'high', name: null, count: 1, total_value: '150.0' },
    ],
    pagination: { next_cursor: null, total_count: 2 },
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

  it('cuts the funnel ordered by assignee into groups, each with the server totals', async () => {
    KanbanBoardsAPI.getBoardCards.mockResolvedValue(assigneeCardsResponse());
    const { fetchList, groupBy, groups } = buildListData();

    groupBy.value = 'assignee';
    await fetchList();

    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenCalledWith(3, {
      limit: 20,
      group_by: 'assignee',
      priorities: ['high'],
    });
    expect(groups.value).toMatchObject([
      {
        key: 'unassigned',
        name: 'KANBAN.LIST.GROUP_BY.UNASSIGNED',
        cardsCount: 3,
        totalValue: '80.0',
        hasMore: false,
      },
      { key: '1', name: 'Ana', cardsCount: 2, totalValue: '150.0' },
    ]);
    // Every group but the one holding the last loaded card is already complete.
    expect(groups.value[1].hasMore).toBe(true);
    expect(groups.value.map(group => group.cards.map(card => card.id))).toEqual(
      [[12], [11]]
    );
  });

  it('cuts the funnel ordered by priority into groups', async () => {
    KanbanBoardsAPI.getBoardCards.mockResolvedValue(priorityCardsResponse());
    const { fetchList, groupBy, groups } = buildListData();

    groupBy.value = 'priority';
    await fetchList();

    expect(groups.value).toMatchObject([
      {
        key: 'none',
        name: 'KANBAN.FILTERS.PRIORITY.NONE',
        cardsCount: 1,
        hasMore: false,
      },
      {
        key: 'high',
        name: 'KANBAN.FILTERS.PRIORITY.HIGH',
        cardsCount: 1,
        totalValue: '150.0',
        hasMore: false,
      },
    ]);
    expect(groups.value.map(group => group.cards.map(card => card.id))).toEqual(
      [[12], [11]]
    );
  });

  it('pages the funnel from its own cursor and restarts it on a criterion change', async () => {
    KanbanBoardsAPI.getBoardCards.mockResolvedValue(assigneeCardsResponse());
    const { fetchList, groupBy, groups, loadMoreForGroup } = buildListData();

    groupBy.value = 'assignee';
    await fetchList();
    await loadMoreForGroup('1');

    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenLastCalledWith(3, {
      limit: 20,
      group_by: 'assignee',
      cursor: { after_id: 11 },
      priorities: ['high'],
    });

    KanbanBoardsAPI.getBoardCards.mockResolvedValue(priorityCardsResponse());
    groupBy.value = 'priority';
    await fetchList();

    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenLastCalledWith(3, {
      limit: 20,
      group_by: 'priority',
      priorities: ['high'],
    });
    expect(groups.value.flatMap(group => group.cards).length).toBe(2);
  });

  it('does not page a group that has no cursor left', async () => {
    const { fetchList, loadMoreForGroup } = buildListData();
    await fetchList();

    await loadMoreForGroup('9');

    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });
});
