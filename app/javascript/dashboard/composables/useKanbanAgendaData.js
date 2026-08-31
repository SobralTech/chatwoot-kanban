import { computed, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import {
  endOfMonth,
  endOfWeek,
  format,
  startOfMonth,
  startOfWeek,
} from 'date-fns';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const PAGE_LIMIT = 50;

export const toDayKey = date => format(date, 'yyyy-MM-dd');

// The grid always renders whole weeks, so the month request has to reach the
// days of the neighbouring months that share its first and last row.
export const monthGridRange = date => ({
  from: startOfWeek(startOfMonth(date)),
  to: endOfWeek(endOfMonth(date)),
});

const normalizeCards = data => camelcaseKeys(data?.cards || [], { deep: true });

/**
 * The agenda's two reads: the grid of a whole month (paged through in one go so
 * switching weeks inside it costs nothing) and the "no due date" bucket, which
 * is independent of the month and grows by cursor.
 */
export function useKanbanAgendaData({ boardId }) {
  const cardsByDay = ref({});
  const cardsWithoutDate = ref([]);
  const withoutDateCount = ref(0);
  const withoutDateCursor = ref(null);
  const isLoading = ref(false);
  const isLoadingWithoutDate = ref(false);
  // A month request is several pages long; a faster month switch must win.
  let monthGeneration = 0;

  const hasMoreWithoutDate = computed(() => !!withoutDateCursor.value);

  const fetchPage = async params => {
    const response = await KanbanBoardsAPI.getBoardCards(boardId.value, {
      limit: PAGE_LIMIT,
      ...params,
    });

    return response.data;
  };

  const fetchAllPages = async (params, collected = []) => {
    const data = await fetchPage(params);
    const cards = [...collected, ...normalizeCards(data)];
    const nextCursor = data.pagination?.next_cursor;

    return nextCursor
      ? fetchAllPages({ ...params, cursor: nextCursor }, cards)
      : cards;
  };

  const groupByDay = cards =>
    cards.reduce((grouped, card) => {
      const key = toDayKey(new Date(card.dueAt));
      grouped[key] = [...(grouped[key] || []), card];
      return grouped;
    }, {});

  const fetchMonth = async date => {
    const { from, to } = monthGridRange(date);
    monthGeneration += 1;
    const generation = monthGeneration;
    isLoading.value = true;

    try {
      const cards = await fetchAllPages({
        due_date_from: from.toISOString(),
        due_date_to: to.toISOString(),
      });
      if (generation !== monthGeneration) return;

      cardsByDay.value = groupByDay(cards);
    } finally {
      if (generation === monthGeneration) isLoading.value = false;
    }
  };

  const fetchWithoutDate = async ({ reset = false } = {}) => {
    const cursor = reset ? undefined : withoutDateCursor.value;
    isLoadingWithoutDate.value = true;

    try {
      const data = await fetchPage({ without_due_date: true, cursor });
      const cards = normalizeCards(data);
      cardsWithoutDate.value = reset
        ? cards
        : [...cardsWithoutDate.value, ...cards];
      withoutDateCursor.value = data.pagination?.next_cursor || null;
      if (data.pagination?.total_count != null) {
        withoutDateCount.value = data.pagination.total_count;
      }
    } finally {
      isLoadingWithoutDate.value = false;
    }
  };

  const fetchMore = () => fetchWithoutDate();

  return {
    cardsByDay,
    cardsWithoutDate,
    fetchMonth,
    fetchMore,
    fetchWithoutDate,
    hasMoreWithoutDate,
    isLoading,
    isLoadingWithoutDate,
    withoutDateCount,
  };
}
