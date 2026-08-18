import { ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

export function useKanbanBoardData({
  collapsedStageIds,
  currentBoardRequestConfig,
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

    const page = await fetchStageCardsPage(stageId, { limit }, generation);
    if (page === staleRequest) return false;
    applyStageFirstPage(stageId, page);
    return true;
  };

  const refreshStageFirstPage = (
    stageId,
    generation = requestGeneration.value,
    { force = false } = {}
  ) => {
    if (!selectedBoard.value?.id || !stageId) return Promise.resolve();
    if (!force && collapsedStageIds.value.has(stageId))
      return Promise.resolve();

    const requestKey = `${generation}:${stageId}`;
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
    const uniqueStageIds = [...new Set(stageIds.filter(Boolean))].filter(
      stageId => !collapsedStageIds.value.has(stageId)
    );
    return Promise.all(
      uniqueStageIds.map(stageId => refreshStageFirstPage(stageId))
    );
  };

  const clearStageCards = stageId => {
    updateStageCards(stageId, stage => ({ ...stage, cards: [] }));
  };

  const updateStageSummary = (stageId, { countDelta = 0, valueDelta = 0 }) => {
    updateStageCards(stageId, stage => {
      const totalCount = (stage.cardsCount || 0) + countDelta;
      const totalValue = (stage.totalValue || 0) + valueDelta;

      return {
        ...stage,
        cardsCount: totalCount,
        totalValue,
        pagination: {
          ...stage.pagination,
          totalCount,
          totalValue,
        },
      };
    });
  };

  const findCardStageId = card => {
    if (card?.kanbanStageId) return card.kanbanStageId;

    return stages.value.find(stage =>
      stage.cards.some(item => item.id === card?.id)
    )?.id;
  };

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

    return true;
  };

  const loadMoreStageCards = async stage => {
    if (
      !selectedBoard.value?.id ||
      !stage?.id ||
      collapsedStageIds.value.has(stage.id) ||
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

    try {
      const response = await KanbanBoardsAPI.showBoard(
        boardId,
        currentBoardRequestConfig()
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
    clearStageCards,
    fetchStageCardsPage,
    findCardStageId,
    getStageCardsError,
    isStageCardsLoading,
    loadMoreStageCards,
    normalizePayload,
    patchVisibleCard,
    refreshStageFirstPage,
    refreshStageFirstPages,
    requestGeneration,
    showBoard,
    staleRequest,
    updateStageSummary,
  };
}
