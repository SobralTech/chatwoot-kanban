import { computed, onUnmounted, ref } from 'vue';

import {
  applyMatchModeConstraints,
  DEFAULT_TERMINAL_PERIOD,
} from 'dashboard/helper/kanbanBoardFilters';

export function useKanbanBoardFiltersState({
  currentUserId,
  isFetchingBoard,
  stages,
}) {
  const emptyBoardFilters = () => ({
    inboxIds: [],
    assigneeIds: [],
    cardStatuses: [],
    priorities: [],
    dueDates: [],
    labels: [],
    matchMode: 'any',
  });

  const normalizeBoardFilters = filters =>
    applyMatchModeConstraints({
      inboxIds: [...new Set(filters?.inboxIds || [])],
      assigneeIds: [...new Set(filters?.assigneeIds || [])],
      cardStatuses: [...new Set(filters?.cardStatuses || [])],
      priorities: [...new Set(filters?.priorities || [])],
      dueDates: [...new Set(filters?.dueDates || [])],
      labels: [...new Set(filters?.labels || [])],
      matchMode: filters?.matchMode === 'all' ? 'all' : 'any',
    });

  const boardFilters = ref(emptyBoardFilters());
  const terminalPeriod = ref(DEFAULT_TERMINAL_PERIOD);
  const searchInput = ref('');
  const activeSearchTerm = ref('');
  let searchDebounceTimer = null;
  const clearSearchDebounce = () => {
    clearTimeout(searchDebounceTimer);
    searchDebounceTimer = null;
  };

  const scheduleSearch = callback => {
    clearSearchDebounce();
    searchDebounceTimer = setTimeout(callback, 350);
  };

  const activeBoardFilterCount = computed(() =>
    [
      boardFilters.value.inboxIds,
      boardFilters.value.assigneeIds,
      boardFilters.value.cardStatuses,
      boardFilters.value.priorities,
      boardFilters.value.dueDates,
      boardFilters.value.labels,
    ].reduce((count, values) => count + values.length, 0)
  );
  const hasActiveBoardFilters = computed(
    () => activeBoardFilterCount.value > 0
  );
  const hasActiveFilters = computed(
    () => hasActiveBoardFilters.value || activeSearchTerm.value.length >= 2
  );
  const isSearchLoading = computed(
    () => isFetchingBoard.value && searchInput.value !== ''
  );
  const searchResultCount = computed(() =>
    stages.value.reduce((total, stage) => total + (stage.cardsCount || 0), 0)
  );
  const hasNoSearchResults = computed(
    () => activeSearchTerm.value.length >= 2 && searchResultCount.value === 0
  );
  const isMineActive = computed(() =>
    Boolean(
      currentUserId.value &&
        boardFilters.value.assigneeIds.includes(currentUserId.value)
    )
  );
  const isTodayActive = computed(() =>
    ['overdue', 'day'].every(value =>
      boardFilters.value.dueDates.includes(value)
    )
  );
  const todayCardsCount = computed(() => searchResultCount.value);

  const currentBoardFilterParams = () => {
    const params = {};
    const filterParams = {
      inboxIds: 'inbox_ids',
      assigneeIds: 'assignee_ids',
      cardStatuses: 'card_statuses',
      priorities: 'priorities',
      dueDates: 'due_dates',
      labels: 'labels',
    };

    Object.entries(filterParams).forEach(([filterKey, paramKey]) => {
      if (boardFilters.value[filterKey].length > 0) {
        params[paramKey] = boardFilters.value[filterKey];
      }
    });

    if (Object.keys(params).length > 0) {
      params.match_mode = boardFilters.value.matchMode;
    }

    return params;
  };

  const currentSearchParams = () =>
    activeSearchTerm.value.length >= 2 ? { q: activeSearchTerm.value } : {};

  // The period slices the two terminal columns only, so it is sent as a param
  // but deliberately left out of activeBoardFilterCount, which gates whether
  // cards can be dragged and reordered across the whole board.
  const currentTerminalPeriodParams = () =>
    terminalPeriod.value === DEFAULT_TERMINAL_PERIOD
      ? {}
      : { terminal_period: terminalPeriod.value };

  const currentFilterParams = () => ({
    ...currentBoardFilterParams(),
    ...currentSearchParams(),
    ...currentTerminalPeriodParams(),
  });

  onUnmounted(() => {
    clearSearchDebounce();
  });

  return {
    activeBoardFilterCount,
    activeSearchTerm,
    boardFilters,
    clearSearchDebounce,
    currentFilterParams,
    emptyBoardFilters,
    hasActiveBoardFilters,
    hasActiveFilters,
    hasNoSearchResults,
    isMineActive,
    isSearchLoading,
    isTodayActive,
    normalizeBoardFilters,
    scheduleSearch,
    searchInput,
    terminalPeriod,
    todayCardsCount,
  };
}
