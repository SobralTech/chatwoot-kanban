import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
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

// The funnel endpoint names the card priority `priority`; the row reads the name
// the board payload uses.
const normalizeCard = rawCard => ({
  ...camelcaseKeys(rawCard, { deep: true }),
  cardPriority: rawCard.priority,
});

// The assignee a card is grouped under: the first by name, the same one the
// server ordered the funnel by, so a card with several lands in one group only.
const primaryAssigneeId = card =>
  [...(card.assignees || [])].sort(
    (first, second) =>
      first.name.toLowerCase().localeCompare(second.name.toLowerCase()) ||
      first.id - second.id
  )[0]?.id;

const GROUP_KEY_READERS = {
  assignee: card => String(primaryAssigneeId(card) ?? 'unassigned'),
  priority: card => card.cardPriority || 'none',
};

// Only the assignee groups are named by the server; a priority group is named by
// the same label the filter menu already gives that priority.
const GROUP_LABEL_KEYS = {
  assignee: () => 'KANBAN.LIST.GROUP_BY.UNASSIGNED',
  priority: key => `KANBAN.FILTERS.PRIORITY.${key.toUpperCase()}`,
};

/**
 * The list reads the funnel one group at a time. Grouped by stage, the board
 * request brings every stage already ordered, with its first page of cards, its
 * count and its value total, and each stage pages on from there. Grouped by
 * assignee or priority, the funnel endpoint answers with the cards already
 * ordered by the criterion plus a summary per group: the list is cut where the
 * criterion changes, and every group but the last one loaded is complete.
 */
export function useKanbanListData({
  board,
  boardId,
  currentFilterParams,
  isLoading,
}) {
  const { t } = useI18n();

  const groupBy = ref('stage');
  const loadingGroupKeys = ref([]);
  const cards = ref([]);
  const cardGroups = ref([]);
  const nextCursor = ref(null);

  const isStageGrouping = computed(() => groupBy.value === 'stage');
  const groupKeyOf = card => GROUP_KEY_READERS[groupBy.value](card);

  const stageGroups = computed(() =>
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

  const criterionGroups = computed(() => {
    const lastCard = cards.value[cards.value.length - 1];
    const partialGroupKey = lastCard ? groupKeyOf(lastCard) : null;

    return cardGroups.value.map(group => ({
      key: group.key,
      name: group.name || t(GROUP_LABEL_KEYS[groupBy.value](group.key)),
      cards: cards.value.filter(card => groupKeyOf(card) === group.key),
      cardsCount: group.count,
      totalValue: group.totalValue,
      hasMore: !!nextCursor.value && group.key === partialGroupKey,
    }));
  });

  const groups = computed(() =>
    isStageGrouping.value ? stageGroups.value : criterionGroups.value
  );

  const isGroupLoading = groupKey => loadingGroupKeys.value.includes(groupKey);

  const findStage = stageId =>
    board.value?.stages?.find(stage => stage.id === stageId);

  const fetchCriterionPage = async cursor => {
    const { data } = await KanbanBoardsAPI.getBoardCards(boardId.value, {
      limit: PAGE_LIMIT,
      group_by: groupBy.value,
      ...(cursor ? { cursor } : {}),
      ...currentFilterParams(),
    });
    const page = (data.cards || []).map(normalizeCard);

    cards.value = cursor ? [...cards.value, ...page] : page;
    nextCursor.value = data.pagination?.next_cursor || null;
    if (!cursor) cardGroups.value = camelcaseKeys(data.groups || []);
  };

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
      if (!isStageGrouping.value) await fetchCriterionPage();
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

  const fetchStagePage = async groupKey => {
    const stage = findStage(Number(groupKey));
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
  };

  const hasMoreInGroup = groupKey =>
    isStageGrouping.value
      ? !!findStage(Number(groupKey))?.nextCursor
      : !!nextCursor.value;

  const loadMoreForGroup = async groupKey => {
    if (isGroupLoading(groupKey) || !hasMoreInGroup(groupKey)) return;

    loadingGroupKeys.value = [...loadingGroupKeys.value, groupKey];

    try {
      if (isStageGrouping.value) await fetchStagePage(groupKey);
      else await fetchCriterionPage(nextCursor.value);
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
