import { computed, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const PAGE_LIMIT = 20;

// The cursor is an opaque object the server hands back and reads again, so it is
// taken from the raw payload instead of the camel-cased copy.
const normalizeStage = rawStage => ({
  ...camelcaseKeys(rawStage, { deep: true }),
  cardsCount: rawStage.pagination?.total_count ?? 0,
  totalValue: rawStage.pagination?.total_value,
  nextCursor: rawStage.pagination?.next_cursor || null,
});

/**
 * The list reads the funnel one group at a time: the board request brings every
 * group already ordered, with its first page of cards, its count and its value
 * total, and each group pages on from there without touching the others.
 */
export function useKanbanListData({
  board,
  boardId,
  currentFilterParams,
  isLoading,
}) {
  // Only stage grouping is served here; the other criteria come with the
  // "group by" dropdown and read the board cards endpoint instead.
  const groupBy = ref('stage');
  const loadingGroupKeys = ref([]);

  const groups = computed(() =>
    (board.value?.stages || []).map(stage => ({
      key: String(stage.id),
      stageId: stage.id,
      name: stage.name,
      color: stage.color,
      cards: stage.cards || [],
      cardsCount: stage.cardsCount,
      totalValue: stage.totalValue,
      hasMore: !!stage.nextCursor,
    }))
  );

  const isGroupLoading = groupKey => loadingGroupKeys.value.includes(groupKey);

  const findStage = stageId =>
    board.value?.stages?.find(stage => stage.id === stageId);

  const fetchList = async () => {
    isLoading.value = true;

    try {
      const { data } = await KanbanBoardsAPI.showBoard(boardId.value, {
        params: currentFilterParams(),
      });
      board.value = {
        ...camelcaseKeys(data, { deep: true }),
        stages: (data.stages || []).map(normalizeStage),
      };
    } finally {
      isLoading.value = false;
    }
  };

  const appendStagePage = (stage, data) => {
    const loadedIds = new Set(stage.cards.map(card => card.id));
    const nextCards = camelcaseKeys(data.cards || [], { deep: true });

    stage.cards = [
      ...stage.cards,
      ...nextCards.filter(card => !loadedIds.has(card.id)),
    ];
    stage.nextCursor = data.pagination?.next_cursor || null;
  };

  const loadMoreForGroup = async groupKey => {
    const stage = findStage(Number(groupKey));
    if (!stage?.nextCursor || isGroupLoading(groupKey)) return;

    loadingGroupKeys.value = [...loadingGroupKeys.value, groupKey];

    try {
      const { data } = await KanbanBoardsAPI.getStageCards(
        boardId.value,
        stage.id,
        {
          limit: PAGE_LIMIT,
          cursor: stage.nextCursor,
          ...currentFilterParams(),
        }
      );
      appendStagePage(stage, data);
    } finally {
      loadingGroupKeys.value = loadingGroupKeys.value.filter(
        key => key !== groupKey
      );
    }
  };

  return {
    fetchList,
    groupBy,
    groups,
    isGroupLoading,
    isLoading,
    loadMoreForGroup,
  };
}
