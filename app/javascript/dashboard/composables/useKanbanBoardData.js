import { ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

export function useKanbanBoardData({
  collapsedStageIds,
  currentFilterParams,
  hasError,
  isFetchingBoard,
  route,
  router,
  selectedBoard,
  stages,
  t,
}) {
  const stageCardsPageLimit = 20;
  const stageCardsLoading = ref({});
  const stageCardsErrors = ref({});
  const stageRefreshRequests = new Map();
  const stageDataVersions = new Map();
  const requestGeneration = ref(0);
  const staleRequest = Symbol('stale-kanban-request');
  const boardSummary = ref({});
  const isFetchingSummary = ref(false);
  const summaryError = ref(false);

  // Collapsed columns are a per-user view preference rather than a filter, so
  // the board request carries them next to the shared filter params.
  const boardRequestConfig = () => {
    const params = { ...currentFilterParams() };
    if (collapsedStageIds.value.size) {
      params.collapsed_stage_ids = [...collapsedStageIds.value];
    }

    return Object.keys(params).length ? { params } : undefined;
  };

  const normalizePayload = data => camelcaseKeys(data || {}, { deep: true });

  const normalizeKanbanPayload = data => {
    const payload = normalizePayload(data);

    if (data?.pagination) {
      payload.pagination = {
        ...payload.pagination,
        nextCursor: data.pagination.next_cursor,
      };
    }

    if (data?.stages) {
      payload.stages = payload.stages.map((stage, index) => ({
        ...stage,
        pagination: data.stages[index]?.pagination
          ? {
              ...stage.pagination,
              nextCursor: data.stages[index].pagination.next_cursor,
            }
          : stage.pagination,
        cardsCount: data.stages[index]?.pagination?.total_count ?? 0,
        totalValue:
          data.stages[index]?.pagination?.total_value ??
          payload.stages[index]?.totalValue,
      }));
    }

    return payload;
  };

  const isRefreshRequiredError = error =>
    error?.response?.status === 409 &&
    error?.response?.data?.error === 'refresh_required';

  const getStageCardsError = stageId => stageCardsErrors.value[stageId] || '';

  const isStageCardsLoading = stageId => !!stageCardsLoading.value[stageId];

  const setStageCardsLoading = (stageId, isLoading) => {
    stageCardsLoading.value = {
      ...stageCardsLoading.value,
      [stageId]: isLoading,
    };
  };

  const setStageCardsError = (stageId, message = '') => {
    stageCardsErrors.value = {
      ...stageCardsErrors.value,
      [stageId]: message,
    };
  };

  const mergeCardsById = (existingCards = [], nextCards = []) => {
    const cardIds = new Set(existingCards.map(card => card.id));
    const uniqueNextCards = nextCards.filter(card => {
      if (cardIds.has(card.id)) return false;

      cardIds.add(card.id);
      return true;
    });

    return [...existingCards, ...uniqueNextCards];
  };

  const updateStageCards = (stageId, updater) => {
    if (!selectedBoard.value) return;

    selectedBoard.value = {
      ...selectedBoard.value,
      stages: selectedBoard.value.stages.map(stage =>
        stage.id === stageId ? updater(stage) : stage
      ),
    };
  };

  const applyStageCardsPage = (stageId, page, shouldAppend = true) => {
    updateStageCards(stageId, stage => ({
      ...stage,
      cards: shouldAppend
        ? mergeCardsById(stage.cards, page.cards)
        : page.cards || [],
      pagination: page.pagination || stage.pagination,
      cardsCount: page.pagination?.totalCount ?? stage.cardsCount,
      totalValue: page.pagination?.totalValue ?? stage.totalValue,
    }));
  };

  const getStageDataVersion = stageId => stageDataVersions.get(stageId) || 0;

  const applyStageFirstPage = (stageId, page) => {
    // Bumping the version lets an in-flight loadMoreStageCards request for
    // this stage detect that its cursor/pagination are now stale and bail
    // out instead of clobbering this fresher replace with a stale append.
    stageDataVersions.set(stageId, getStageDataVersion(stageId) + 1);

    updateStageCards(stageId, stage => ({
      ...stage,
      cards: page.cards || [],
      pagination: page.pagination || stage.pagination,
      cardsCount: page.pagination?.totalCount ?? stage.cardsCount,
      totalValue: page.pagination?.totalValue ?? stage.totalValue,
    }));
    setStageCardsError(stageId);
  };

  const fetchStageCardsPage = async (
    stageId,
    params,
    generation = requestGeneration.value
  ) => {
    const response = await KanbanBoardsAPI.getStageCards(
      selectedBoard.value.id,
      stageId,
      {
        ...params,
        ...currentFilterParams(),
      }
    );

    if (generation !== requestGeneration.value) return staleRequest;
    return normalizeKanbanPayload(response.data);
  };

  const reloadStageCards = async (
    stageId,
    generation = requestGeneration.value
  ) => {
    const stage = stages.value.find(item => item.id === stageId);
    const limit = Math.max(stageCardsPageLimit, stage?.cards?.length || 0);
    // A collapsed column shows no cards but still shows its counters, so it
    // refreshes through the same endpoint asking for totals only.
    const params = collapsedStageIds.value.has(stageId)
      ? { limit, metadata_only: true }
      : { limit };

    const page = await fetchStageCardsPage(stageId, params, generation);
    if (page === staleRequest) return false;
    applyStageFirstPage(stageId, page);
    return true;
  };

  // The summary reads the same filters as the columns, but through its own request
  // so a slow aggregate never holds the board back. The previous numbers stay on
  // screen while it reloads, because it now reloads on every card change.
  const fetchBoardSummary = async (boardId, generation) => {
    isFetchingSummary.value = true;
    summaryError.value = false;

    try {
      const response = await KanbanBoardsAPI.getSummary(boardId, {
        params: currentFilterParams(),
      });
      if (generation !== requestGeneration.value) return;

      boardSummary.value = normalizePayload(response.data);
    } catch {
      if (generation !== requestGeneration.value) return;

      summaryError.value = true;
    } finally {
      if (generation === requestGeneration.value) {
        isFetchingSummary.value = false;
      }
    }
  };

  // The summary aggregates the same cards the columns show, so anything that
  // changes a card changes it too. Queueing rather than fetching means a burst of
  // stage refreshes - a drag touching two columns, a realtime flush, a bulk move -
  // still costs a single request.
  let queuedSummaryRefresh = null;
  const queueBoardSummaryRefresh = () => {
    queuedSummaryRefresh ||= Promise.resolve().then(() => {
      queuedSummaryRefresh = null;
      if (!selectedBoard.value?.id) return;

      fetchBoardSummary(selectedBoard.value.id, requestGeneration.value);
    });
  };

  const refreshStageFirstPage = (
    stageId,
    generation = requestGeneration.value
  ) => {
    if (!selectedBoard.value?.id || !stageId) return Promise.resolve();

    queueBoardSummaryRefresh();

    // The collapsed flag is part of the key so that toggling a column does not
    // reuse an in-flight request fetching the other shape.
    const isCollapsed = collapsedStageIds.value.has(stageId);
    const requestKey = `${generation}:${stageId}:${isCollapsed}`;
    if (stageRefreshRequests.has(requestKey)) {
      return stageRefreshRequests.get(requestKey);
    }

    const request = reloadStageCards(stageId, generation)
      .catch(() =>
        setStageCardsError(stageId, t('KANBAN.ACTIONS.LOAD_CARDS_ERROR'))
      )
      .finally(() => {
        stageRefreshRequests.delete(requestKey);
      });

    stageRefreshRequests.set(requestKey, request);
    return request;
  };

  const refreshStageFirstPages = stageIds => {
    const uniqueStageIds = [...new Set(stageIds.filter(Boolean))];
    return Promise.all(
      uniqueStageIds.map(stageId => refreshStageFirstPage(stageId))
    );
  };

  const findCardStage = card =>
    stages.value.find(stage => stage.cards.some(item => item.id === card?.id));

  const findCardStageId = card =>
    card?.kanbanStageId || findCardStage(card)?.id;

  const patchVisibleCard = card => {
    const updatedCard = normalizePayload(card);
    if (!updatedCard?.id) return false;

    const visibleStage = stages.value.find(stage =>
      stage.cards.some(existingCard => existingCard.id === updatedCard.id)
    );
    if (
      !visibleStage ||
      (updatedCard.kanbanStageId &&
        updatedCard.kanbanStageId !== visibleStage.id)
    ) {
      return false;
    }

    updateStageCards(visibleStage.id, stage => ({
      ...stage,
      cards: stage.cards.map(existingCard =>
        existingCard.id === updatedCard.id
          ? { ...existingCard, ...updatedCard }
          : existingCard
      ),
    }));

    queueBoardSummaryRefresh();
    return true;
  };

  const loadMoreStageCards = async stage => {
    if (
      !selectedBoard.value?.id ||
      !stage?.id ||
      isStageCardsLoading(stage.id)
    ) {
      return;
    }

    const stageId = stage.id;
    const generation = requestGeneration.value;
    const dataVersion = getStageDataVersion(stageId);
    setStageCardsLoading(stageId, true);
    setStageCardsError(stageId);

    try {
      const page = await fetchStageCardsPage(stageId, {
        limit: stageCardsPageLimit,
        cursor: stage.pagination?.nextCursor,
      });

      // A first-page replace (reload or realtime refresh) landed while this
      // request was in flight; this page's cursor/pagination are stale.
      if (
        generation !== requestGeneration.value ||
        getStageDataVersion(stageId) !== dataVersion
      ) {
        return;
      }

      applyStageCardsPage(stageId, page);
    } catch (error) {
      if (isRefreshRequiredError(error)) {
        await reloadStageCards(stageId, generation);
        return;
      }

      if (generation === requestGeneration.value) {
        setStageCardsError(stageId, t('KANBAN.ACTIONS.LOAD_CARDS_ERROR'));
      }
    } finally {
      if (generation === requestGeneration.value) {
        setStageCardsLoading(stageId, false);
      }
    }
  };

  const showBoard = async (boardId, generation = requestGeneration.value) => {
    if (!boardId) {
      selectedBoard.value = null;
      return;
    }

    isFetchingBoard.value = true;
    hasError.value = false;
    fetchBoardSummary(boardId, generation);

    try {
      const response = await KanbanBoardsAPI.showBoard(
        boardId,
        boardRequestConfig()
      );
      if (generation !== requestGeneration.value) return;
      stageCardsLoading.value = {};
      stageCardsErrors.value = {};
      selectedBoard.value = normalizeKanbanPayload(response.data);
    } catch (error) {
      if (generation !== requestGeneration.value) return;
      hasError.value = true;
      if ([403, 404].includes(error?.response?.status)) {
        router.replace({
          name: 'kanban_boards',
          params: { accountId: route.params.accountId },
        });
      }
    } finally {
      if (generation === requestGeneration.value) {
        isFetchingBoard.value = false;
      }
    }
  };

  return {
    applyStageFirstPage,
    boardSummary,
    fetchStageCardsPage,
    findCardStage,
    findCardStageId,
    getStageCardsError,
    isFetchingSummary,
    isStageCardsLoading,
    loadMoreStageCards,
    normalizePayload,
    patchVisibleCard,
    refreshStageFirstPage,
    refreshStageFirstPages,
    requestGeneration,
    showBoard,
    staleRequest,
    summaryError,
  };
}
