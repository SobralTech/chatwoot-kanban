import { ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useKanbanAgendaData } from '../useKanbanAgendaData';

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: { getBoardCards: vi.fn() },
}));

const cardPayload = (id, dueAt) => ({
  id,
  kanban_stage_id: 7,
  due_at: dueAt,
});

const page = (cards, nextCursor = null, totalCount = null) => ({
  data: {
    cards,
    pagination: { next_cursor: nextCursor, total_count: totalCount },
  },
});

describe('useKanbanAgendaData', () => {
  const boardId = ref(3);

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('groups the cards of every page by their due date', async () => {
    KanbanBoardsAPI.getBoardCards
      .mockResolvedValueOnce(
        page(
          [
            cardPayload(1, '2026-08-10T12:00:00.000Z'),
            cardPayload(2, '2026-08-10T18:00:00.000Z'),
          ],
          { after_id: 2 }
        )
      )
      .mockResolvedValueOnce(
        page([cardPayload(3, '2026-08-11T12:00:00.000Z')])
      );

    const { cardsByDay, fetchMonth } = useKanbanAgendaData({ boardId });
    await fetchMonth(new Date(2026, 7, 1));

    expect(Object.keys(cardsByDay.value)).toEqual(['2026-08-10', '2026-08-11']);
    expect(cardsByDay.value['2026-08-10'].map(card => card.id)).toEqual([1, 2]);
    expect(cardsByDay.value['2026-08-11'].map(card => card.id)).toEqual([3]);
  });

  it('requests the whole rendered grid, not only the month itself', async () => {
    KanbanBoardsAPI.getBoardCards.mockResolvedValueOnce(page([]));

    const { fetchMonth } = useKanbanAgendaData({ boardId });
    await fetchMonth(new Date(2026, 7, 1));

    const params = KanbanBoardsAPI.getBoardCards.mock.calls[0][1];
    expect(new Date(params.due_date_from).getDate()).toBe(26);
    expect(new Date(params.due_date_to).getDate()).toBe(5);
  });

  it('keeps the cards without a due date out of the day map', async () => {
    KanbanBoardsAPI.getBoardCards.mockResolvedValueOnce(
      page([cardPayload(9, null)], { after_id: 9 }, 4)
    );

    const {
      cardsByDay,
      cardsWithoutDate,
      fetchWithoutDate,
      hasMoreWithoutDate,
      withoutDateCount,
    } = useKanbanAgendaData({ boardId });
    await fetchWithoutDate({ reset: true });

    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenCalledWith(
      3,
      expect.objectContaining({ without_due_date: true })
    );
    expect(cardsWithoutDate.value.map(card => card.id)).toEqual([9]);
    expect(cardsByDay.value).toEqual({});
    expect(withoutDateCount.value).toBe(4);
    expect(hasMoreWithoutDate.value).toBe(true);
  });
});
