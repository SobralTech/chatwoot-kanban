import { nextTick } from 'vue';

import {
  getKanbanBoardPrefs,
  getKanbanBoardSnapshot,
  removeKanbanBoardSnapshot,
  saveKanbanBoardPrefs,
  saveKanbanBoardSnapshot,
} from 'dashboard/helper/kanbanBoardSnapshot';
import { normalizeTerminalPeriod } from 'dashboard/helper/kanbanBoardFilters';

/**
 * Puts a board back the way its user left it. Two stores answer for that, and
 * they expire differently: preferences persist per user and outlive the tab,
 * while a snapshot is one tab's scroll position, paging and filters, written on
 * the way out to a conversation and consumed the moment the board comes back.
 */
export function useKanbanBoardSession({
  activeSearchTerm,
  applyStageFirstPage,
  boardFilters,
  boardScrollContainer,
  collapsedStageIds,
  currentUserId,
  emptyBoardFilters,
  fetchStageCardsPage,
  isMineActive,
  isStageCollapsed,
  isSummaryCollapsed,
  isTodayActive,
  normalizeBoardFilters,
  pendingScrollToStageId,
  requestGeneration,
  route,
  searchInput,
  selectedBoard,
  showBoard,
  staleRequest,
  stages,
  terminalPeriod,
}) {
  const accountId = () => route.params.accountId;
  const prefsUserId = () => currentUserId.value ?? 'unknown';

  // Restoring runs across several awaits; anything the user does in between —
  // switching boards, filtering, searching — makes the rest of it wrong.
  const isStale = (generation, boardId) =>
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId;

  const loadBoardPrefs = boardId => {
    const prefs = getKanbanBoardPrefs({
      accountId: accountId(),
      boardId,
      userId: prefsUserId(),
    });
    const storedStageIds = Array.isArray(prefs?.collapsedStageIds)
      ? prefs.collapsedStageIds.map(Number).filter(Boolean)
      : [];

    collapsedStageIds.value = new Set(storedStageIds);
    terminalPeriod.value = normalizeTerminalPeriod(prefs?.terminalPeriod);
    isSummaryCollapsed.value = prefs?.summaryCollapsed === true;

    return prefs;
  };

  // Every stored preference is derived from live board state, so persisting is
  // always a full snapshot taken after that state has been updated.
  const persistBoardPrefs = () => {
    if (!selectedBoard.value?.id) return;

    saveKanbanBoardPrefs({
      accountId: accountId(),
      boardId: selectedBoard.value.id,
      userId: prefsUserId(),
      prefs: {
        collapsedStageIds: [...collapsedStageIds.value],
        terminalPeriod: terminalPeriod.value,
        summaryCollapsed: isSummaryCollapsed.value,
        mine: isMineActive.value,
        today: isTodayActive.value,
      },
    });
  };

  const stageScrollElement = stageId =>
    boardScrollContainer.value?.querySelector(
      `[data-stage-scroll-id="${stageId}"]`
    );

  const saveBoardSnapshot = () => {
    if (!selectedBoard.value?.id) return;

    saveKanbanBoardSnapshot({
      accountId: accountId(),
      boardId: selectedBoard.value.id,
      snapshot: {
        scrollLeft: boardScrollContainer.value?.scrollLeft ?? 0,
        stages: Object.fromEntries(
          stages.value.map(stage => [
            stage.id,
            {
              loadedCount: stage.cards.length,
              scrollTop: stageScrollElement(stage.id)?.scrollTop ?? 0,
            },
          ])
        ),
        filters: {
          boardFilters: { ...boardFilters.value },
          searchTerm: activeSearchTerm.value,
        },
      },
    });
  };

  const restorePagedStages = (snapshot, boardId, generation) =>
    Promise.all(
      // showBoard already loaded every stage's first page, so only the stages
      // that had been paged past it need to be re-fetched.
      stages.value.map(async stage => {
        if (isStale(generation, boardId) || isStageCollapsed(stage.id)) return;

        const { loadedCount } = snapshot.stages[stage.id] ?? {};
        if (!loadedCount || loadedCount <= stage.cards.length) return;

        const page = await fetchStageCardsPage(
          stage.id,
          { limit: loadedCount },
          generation
        );
        if (page === staleRequest || isStale(generation, boardId)) return;

        applyStageFirstPage(stage.id, page);
      })
    );

  const restoreScrollPositions = snapshot => {
    if (boardScrollContainer.value) {
      boardScrollContainer.value.scrollLeft = snapshot.scrollLeft;
    }

    stages.value.forEach(stage => {
      const element = stageScrollElement(stage.id);
      if (element) {
        element.scrollTop = snapshot.stages[stage.id]?.scrollTop ?? 0;
      }
    });
  };

  const applyBoardSnapshot = async (snapshot, boardId, generation) => {
    if (isStale(generation, boardId)) return;

    await restorePagedStages(snapshot, boardId, generation);
    if (isStale(generation, boardId)) return;

    await nextTick();
    if (isStale(generation, boardId)) return;

    restoreScrollPositions(snapshot);
  };

  // Without a snapshot the board opens on whatever quick filters the user had
  // last turned on, which live in the preferences rather than the snapshot.
  const applyPreferredFilters = prefs => {
    if (!prefs) return;

    const initialFilters = emptyBoardFilters();
    if (prefs.mine && currentUserId.value) {
      initialFilters.assigneeIds = [currentUserId.value];
      initialFilters.matchMode = 'all';
    }
    if (prefs.today) {
      initialFilters.dueDates = ['overdue', 'day'];
      initialFilters.cardStatuses = ['open'];
      initialFilters.matchMode = 'all';
    }
    boardFilters.value = normalizeBoardFilters(initialFilters);
  };

  const applySnapshotFilters = snapshot => {
    boardFilters.value = normalizeBoardFilters(
      snapshot.filters?.boardFilters || {
        inboxIds: snapshot.filters?.inboxIds,
        assigneeIds: snapshot.filters?.assigneeIds,
      }
    );
    searchInput.value = snapshot.filters?.searchTerm || '';
    activeSearchTerm.value = snapshot.filters?.searchTerm || '';
  };

  const showBoardWithSnapshot = async (boardId, restoreSnapshot = true) => {
    const generation = requestGeneration.value;
    const prefs = loadBoardPrefs(boardId);
    const snapshot = restoreSnapshot
      ? getKanbanBoardSnapshot({ accountId: accountId(), boardId })
      : null;

    // A snapshot is good for one restore; arriving without one means the board
    // was opened fresh, and any stale snapshot has to go.
    if (!restoreSnapshot) {
      removeKanbanBoardSnapshot({ accountId: accountId(), boardId });
    }

    if (!snapshot || !restoreSnapshot) {
      applyPreferredFilters(prefs);
      await showBoard(boardId, generation);
      return;
    }

    applySnapshotFilters(snapshot);

    if (generation !== requestGeneration.value) return;
    await showBoard(boardId, generation);
    if (isStale(generation, boardId)) return;

    await applyBoardSnapshot(snapshot, boardId, generation);
    if (isStale(generation, boardId)) return;

    removeKanbanBoardSnapshot({ accountId: accountId(), boardId });
  };

  // A reload keeps the horizontal position the user was at, unless something
  // asked to bring a particular stage into view.
  const refreshSelectedBoard = async () => {
    if (!selectedBoard.value?.id) return;

    const savedScrollLeft = boardScrollContainer.value?.scrollLeft ?? 0;
    const targetStageId = pendingScrollToStageId.value;

    const generation = requestGeneration.value;
    await showBoard(selectedBoard.value.id, generation);
    if (generation !== requestGeneration.value) return;
    await nextTick();

    const container = boardScrollContainer.value;
    if (targetStageId) {
      pendingScrollToStageId.value = null;
      container
        ?.querySelector(`[data-stage-id="${targetStageId}"]`)
        ?.scrollIntoView({
          behavior: 'smooth',
          block: 'nearest',
          inline: 'start',
        });
      return;
    }

    if (savedScrollLeft > 0 && container)
      container.scrollLeft = savedScrollLeft;
  };

  return {
    persistBoardPrefs,
    refreshSelectedBoard,
    saveBoardSnapshot,
    showBoardWithSnapshot,
  };
}
