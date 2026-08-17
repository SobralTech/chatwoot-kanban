<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanRealtimeBuffer } from 'dashboard/composables/useKanbanRealtimeBuffer';
import { useKanbanDragAutoScroll } from 'dashboard/composables/useKanbanDragAutoScroll';
import { useKanbanBoardFiltersState } from 'dashboard/composables/useKanbanBoardFiltersState';
import { useKanbanBoardData } from 'dashboard/composables/useKanbanBoardData';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import KanbanStageColumn from './board/KanbanStageColumn.vue';
import KanbanBoardHeader from './board/KanbanBoardHeader.vue';
import KanbanStageDraft from './board/KanbanStageDraft.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { pushEmbedded } from 'dashboard/helper/embeddedConversationHistory';
import {
  getKanbanBoardPrefs,
  getKanbanBoardSnapshot,
  removeKanbanBoardSnapshot,
  saveKanbanBoardPrefs,
  saveKanbanBoardSnapshot,
} from 'dashboard/helper/kanbanBoardSnapshot';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import KanbanOpportunityDetailsModal from './KanbanOpportunityDetailsModal.vue';
import KanbanOpportunityPicker from './KanbanOpportunityPicker.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();

const currentUserId = useMapGetter('getCurrentUserID');
const agents = useMapGetter('agents/getAgents');
const boards = useMapGetter('kanbanBoards/kanbanBoards');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const isFetchingBoards = useMapGetter('kanbanBoards/kanbanBoardsLoading');
const { isAdmin } = useAdmin();
const selectedBoard = ref(null);
const isFetchingBoard = ref(false);
const isCreatingStage = ref(false);
const isCreatingStageDraft = ref(false);
const selectedOpportunityCardId = ref(null);
const opportunityModalRef = ref(null);
const showUnsavedOpportunityChangesConfirm = ref(false);
const isSavingOpportunityBeforeExit = ref(false);
// Keyed by the thing being acted on, not by the verb, so a new action never has
// to be registered anywhere for its spinner to work.
const activeActionKeys = ref(new Set());
const startAction = key => activeActionKeys.value.add(key);
const endAction = key => activeActionKeys.value.delete(key);
const isActionActive = key => activeActionKeys.value.has(key);
const isBoardBusy = computed(() => activeActionKeys.value.size > 0);
const stageActionKey = stage => `stage-${stage.id}`;
const cardActionKey = card => `card-${card.id}`;
const isCardBusy = (card, stage) =>
  isActionActive(cardActionKey(card)) || isActionActive(stageActionKey(stage));
const hasError = ref(false);
const isBoardDropdownOpen = ref(false);
const editingStageId = ref(null);
const stageNames = ref({});
const stageColors = ref({});
const stageNameInputs = new Map();
const activeAddItemStageId = ref(null);
const addItemPickerRef = ref(null);
const showDiscardAddItemConfirm = ref(false);
const highlightedCreatedCardId = ref(null);
let createdCardHighlightTimer = null;
const cardPendingRemoval = ref(null);
const stagePendingRemoval = ref(null);
const stageCardsPendingRemoval = ref(null);
const showRemoveCardConfirmation = ref(false);
const showRemoveStageConfirmation = ref(false);
const showRemoveStageCardsConfirmation = ref(false);
const isCardDragging = ref(false);
const pendingRealtimeKanbanEvents = ref([]);
const hasCardDragChanged = ref(false);
const suppressNextCardClick = ref(false);
const isPersistingCardDrag = ref(false);
const renamingBoardId = ref(null);
const renameValue = ref('');
const isRenamingBoard = ref(false);
const defaultStageColor = DEFAULT_KANBAN_STAGE_COLOR;
const newStageColor = ref(defaultStageColor);
const newStageName = ref('');
const newStageNameInput = ref(null);
const boardScrollContainer = ref(null);
const {
  isDraggingBoard,
  sortableFallbackOptions,
  startBoardAutoScroll,
  stopBoardAutoScroll,
} = useKanbanDragAutoScroll(boardScrollContainer);
const pendingScrollToStageId = ref(null);
let searchRequestToken = 0;
const preSearchScrollLeft = ref(null);

const interactiveDragFilter =
  'button,a,input,textarea,select,[contenteditable="true"],.no-drag';
const boardRefreshEvents = new Set([
  'kanban.board.updated',
  'kanban.stage.created',
  'kanban.stage.updated',
  'kanban.stage.deleted',
  'kanban.stage.reordered',
]);

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const stages = computed(() => selectedBoard.value?.stages || []);
const {
  activeBoardFilterCount,
  activeSearchTerm,
  boardFilters,
  currentBoardRequestConfig,
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
  todayCardsCount,
} = useKanbanBoardFiltersState({
  currentUserId,
  isFetchingBoard,
  stages,
});
const {
  applyStageFirstPage,
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
} = useKanbanBoardData({
  currentBoardRequestConfig,
  currentFilterParams,
  hasError,
  isFetchingBoard,
  route,
  router,
  selectedBoard,
  stages,
  t,
});
const hasBoards = computed(() => boards.value.length > 0);
const activeAddItemStage = computed(() =>
  stages.value.find(stage => stage.id === activeAddItemStageId.value)
);
const isInitialLoading = computed(
  () => isFetchingBoards.value && !selectedBoard.value
);
const isReloadingBoard = computed(
  () => isFetchingBoard.value && !!selectedBoard.value
);
const currentBoardName = computed(
  () => selectedBoard.value?.name || t('KANBAN.NO_BOARD_SELECTED')
);
const boardAllowedInboxIds = computed(
  () => selectedBoard.value?.allowedInboxIds || []
);
const inboxFilterOptions = computed(() => {
  const availableInboxes =
    selectedBoard.value?.inboxScopeMode === 'selected_inboxes'
      ? inboxes.value.filter(inbox =>
          boardAllowedInboxIds.value.includes(inbox.id)
        )
      : inboxes.value;

  return availableInboxes.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }));
});
const agentFilterOptions = computed(() =>
  agents.value.map(agent => ({
    value: agent.id,
    label: agent.name || agent.email,
  }))
);
// The board payload already applies the board's visibility rules server-side.
const assignableUsers = computed(
  () => selectedBoard.value?.assignableUsers || []
);
const stageListModel = computed({
  get: () => selectedBoard.value?.stages || [],
  set: nextStages => {
    if (!selectedBoard.value) return;

    selectedBoard.value = { ...selectedBoard.value, stages: nextStages };
  },
});
const { isTerminalStage, stageTone, canMoveStage } = useKanbanStageOrder({
  stages,
  wonStageId: computed(() => selectedBoard.value?.wonStageId),
  lostStageId: computed(() => selectedBoard.value?.lostStageId),
});
// Tailwind needs literal class names, so the won/lost accents live in one map
// instead of being re-derived at every binding.
const TERMINAL_STAGE_CLASSES = {
  won: {
    border: 'border-n-teal-8',
    header: 'bg-n-teal-2',
    dot: 'bg-n-teal-9',
    title: 'text-n-teal-11',
  },
  lost: {
    border: 'border-n-ruby-8',
    header: 'bg-n-ruby-2',
    dot: 'bg-n-ruby-9',
    title: 'text-n-ruby-11',
  },
};
const stageAccent = stage => TERMINAL_STAGE_CLASSES[stageTone(stage)] ?? null;
const isCardDragDisabled = computed(
  () =>
    isPersistingCardDrag.value || isBoardBusy.value || hasActiveFilters.value
);
const canAddCardInEmptyStage = stage =>
  !isTerminalStage(stage) && !hasActiveFilters.value && !isCardDragging.value;
const canAddCardInStageFooter = stage =>
  !isTerminalStage(stage) && stage.cards.length > 0;
const emptyCardsLabel = computed(() =>
  hasActiveFilters.value
    ? t('KANBAN.EMPTY_CARDS_FILTERED')
    : t('KANBAN.EMPTY_CARDS')
);

const getErrorMessage = (error, fallbackMessage) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallbackMessage;

const isNameTakenError = error => {
  const errorMessage = String(getErrorMessage(error, '')).toLowerCase();
  return errorMessage.includes('name') && errorMessage.includes('taken');
};

const isSpecialStageOrderError = error =>
  error?.response?.data?.error === 'special_stages_must_be_last';

const stageActionErrorMessage = error => {
  switch (error?.response?.data?.error) {
    case 'stage_not_empty':
      return t('KANBAN.STAGE_MENU.ERRORS.STAGE_NOT_EMPTY');
    case 'special_stage_cannot_move_board':
      return t('KANBAN.STAGE_MENU.ERRORS.SPECIAL_STAGE_CANNOT_MOVE_BOARD');
    case 'special_stage_cannot_be_deleted':
      return t('KANBAN.ACTIONS.REMOVE_STAGE_TERMINAL');
    case 'terminal_stage_not_allowed':
      return t('KANBAN.STAGE_MENU.ERRORS.TERMINAL_STAGE_NOT_ALLOWED');
    default:
      return null;
  }
};

const showActionError = (error, fallbackMessage) => {
  let message = getErrorMessage(error, fallbackMessage);
  const stageActionMessage = stageActionErrorMessage(error);
  if (isNameTakenError(error)) message = t('KANBAN.ACTIONS.STAGE_NAME_TAKEN');
  if (isSpecialStageOrderError(error))
    message = t('KANBAN.ACTIONS.STAGE_ORDER_INVALID');
  if (stageActionMessage) message = stageActionMessage;

  useAlert(message);
};

const isLostReasonRequiredError = error =>
  error?.response?.data?.error === 'lost_reason_required';

const getStageScrollElement = stageId =>
  boardScrollContainer.value?.querySelector(
    `[data-stage-scroll-id="${stageId}"]`
  );

const saveBoardSnapshot = () => {
  if (!selectedBoard.value?.id) return;

  saveKanbanBoardSnapshot({
    accountId: route.params.accountId,
    boardId: selectedBoard.value.id,
    snapshot: {
      scrollLeft: boardScrollContainer.value?.scrollLeft ?? 0,
      stages: Object.fromEntries(
        stages.value.map(stage => [
          stage.id,
          {
            loadedCount: stage.cards.length,
            scrollTop: getStageScrollElement(stage.id)?.scrollTop ?? 0,
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

const applyBoardSnapshot = async (snapshot, boardId, generation) => {
  if (
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId
  ) {
    return;
  }

  // showBoard already loaded every stage's first page, so only the stages
  // that had been paged past it need to be re-fetched.
  await Promise.all(
    stages.value.map(async stage => {
      if (
        generation !== requestGeneration.value ||
        selectedBoard.value?.id !== boardId
      ) {
        return;
      }

      const { loadedCount } = snapshot.stages[stage.id] ?? {};
      if (!loadedCount || loadedCount <= stage.cards.length) return;

      const page = await fetchStageCardsPage(
        stage.id,
        { limit: loadedCount },
        generation
      );
      if (
        page === staleRequest ||
        generation !== requestGeneration.value ||
        selectedBoard.value?.id !== boardId
      ) {
        return;
      }
      applyStageFirstPage(stage.id, page);
    })
  );

  if (
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId
  ) {
    return;
  }
  await nextTick();

  if (
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId
  ) {
    return;
  }
  if (boardScrollContainer.value) {
    boardScrollContainer.value.scrollLeft = snapshot.scrollLeft;
  }

  stages.value.forEach(stage => {
    const stageScrollElement = getStageScrollElement(stage.id);
    if (stageScrollElement) {
      stageScrollElement.scrollTop = snapshot.stages[stage.id]?.scrollTop ?? 0;
    }
  });
};

const showBoardWithSnapshot = async (boardId, restoreSnapshot = true) => {
  const generation = requestGeneration.value;
  const snapshot = restoreSnapshot
    ? getKanbanBoardSnapshot({
        accountId: route.params.accountId,
        boardId,
      })
    : null;

  if (!restoreSnapshot) {
    removeKanbanBoardSnapshot({
      accountId: route.params.accountId,
      boardId,
    });
  }

  if (!snapshot || !restoreSnapshot) {
    const prefs = getKanbanBoardPrefs({
      accountId: route.params.accountId,
      boardId,
    });
    if (prefs) {
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
    }
    await showBoard(boardId, generation);
    return;
  }

  boardFilters.value = normalizeBoardFilters(
    snapshot.filters?.boardFilters || {
      inboxIds: snapshot.filters?.inboxIds,
      assigneeIds: snapshot.filters?.assigneeIds,
    }
  );
  searchInput.value = snapshot.filters?.searchTerm || '';
  activeSearchTerm.value = snapshot.filters?.searchTerm || '';

  if (generation !== requestGeneration.value) return;
  await showBoard(boardId, generation);
  if (
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId
  ) {
    return;
  }

  await applyBoardSnapshot(snapshot, boardId, generation);
  if (
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId
  ) {
    return;
  }
  removeKanbanBoardSnapshot({
    accountId: route.params.accountId,
    boardId,
  });
};

const refreshSelectedBoard = async () => {
  if (!selectedBoard.value?.id) return;

  const scrollEl = boardScrollContainer.value;
  const savedScrollLeft = scrollEl?.scrollLeft ?? 0;
  const targetStageId = pendingScrollToStageId.value;

  const generation = requestGeneration.value;
  await showBoard(selectedBoard.value.id, generation);
  if (generation !== requestGeneration.value) return;
  await nextTick();

  const scrollElAfter = boardScrollContainer.value;
  if (targetStageId) {
    pendingScrollToStageId.value = null;
    scrollElAfter
      ?.querySelector(`[data-stage-id="${targetStageId}"]`)
      ?.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest',
        inline: 'start',
      });
  } else if (savedScrollLeft > 0 && scrollElAfter) {
    scrollElAfter.scrollLeft = savedScrollLeft;
  }
};

const scrollToFirstMatchingStage = async () => {
  await nextTick();
  const firstMatch = stages.value.find(stage => stage.cards.length > 0);
  if (!firstMatch) return;

  boardScrollContainer.value
    ?.querySelector(`[data-stage-id="${firstMatch.id}"]`)
    ?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'start' });
};

const restorePreSearchScroll = () => {
  if (preSearchScrollLeft.value === null || !boardScrollContainer.value) return;
  boardScrollContainer.value.scrollLeft = preSearchScrollLeft.value;
  preSearchScrollLeft.value = null;
};

const runSearch = async () => {
  const term = searchInput.value.trim();
  const nextTerm = term.length >= 2 ? term : '';
  if (nextTerm === activeSearchTerm.value) return;

  searchRequestToken += 1;
  requestGeneration.value += 1;
  const token = searchRequestToken;
  if (!activeSearchTerm.value && nextTerm) {
    preSearchScrollLeft.value = boardScrollContainer.value?.scrollLeft ?? 0;
  }
  activeSearchTerm.value = nextTerm;
  const generation = requestGeneration.value;
  await refreshSelectedBoard();
  if (token !== searchRequestToken || generation !== requestGeneration.value)
    return;
  if (nextTerm) await scrollToFirstMatchingStage();
  else if (generation === requestGeneration.value) restorePreSearchScroll();
};

const clearSearch = () => {
  searchInput.value = '';
};
const onSearchKeydown = event => {
  if (event.key !== 'Escape' || searchInput.value === '') return;
  event.preventDefault();
  clearSearch();
};

const persistBoardPrefs = prefs => {
  if (!selectedBoard.value?.id) return;
  saveKanbanBoardPrefs({
    accountId: route.params.accountId,
    boardId: selectedBoard.value.id,
    prefs,
  });
};

const updateBoardFilters = async filters => {
  boardFilters.value = normalizeBoardFilters(filters);
  persistBoardPrefs({
    mine: isMineActive.value,
    today: isTodayActive.value,
  });
  requestGeneration.value += 1;
  await refreshSelectedBoard();
};

const clearBoardFilters = () => {
  persistBoardPrefs({
    mine: false,
    today: false,
  });
  updateBoardFilters(emptyBoardFilters());
};

const toggleMine = () => {
  if (!currentUserId.value) return;
  const willBeActive = !isMineActive.value;
  const nextAssigneeIds = willBeActive
    ? [...new Set([...boardFilters.value.assigneeIds, currentUserId.value])]
    : boardFilters.value.assigneeIds.filter(id => id !== currentUserId.value);

  const nextFilters = {
    ...boardFilters.value,
    assigneeIds: nextAssigneeIds,
  };

  if (willBeActive) {
    nextFilters.matchMode = 'all';
  }

  persistBoardPrefs({
    mine: willBeActive,
    today: isTodayActive.value,
  });
  updateBoardFilters(nextFilters);
};

const toggleToday = () => {
  const willBeActive = !isTodayActive.value;
  let nextDueDates;
  let nextCardStatuses;

  if (willBeActive) {
    nextDueDates = [
      ...new Set([...boardFilters.value.dueDates, 'overdue', 'day']),
    ];
    nextCardStatuses = [
      ...new Set([...boardFilters.value.cardStatuses, 'open']),
    ];
  } else {
    nextDueDates = boardFilters.value.dueDates.filter(
      v => v !== 'overdue' && v !== 'day'
    );
    nextCardStatuses = boardFilters.value.cardStatuses.filter(
      v => v !== 'open'
    );
  }

  const nextFilters = {
    ...boardFilters.value,
    dueDates: nextDueDates,
    cardStatuses: nextCardStatuses,
  };

  if (willBeActive) {
    nextFilters.matchMode = 'all';
  }

  persistBoardPrefs({
    mine: isMineActive.value,
    today: willBeActive,
  });
  updateBoardFilters(nextFilters);
};

const openBoardSettings = () => {
  if (!selectedBoard.value?.id) return;

  router.push({
    name: 'kanban_board_edit_form',
    params: {
      accountId: route.params.accountId,
      boardId: selectedBoard.value.id,
    },
  });
};

const setStageNameInput = (stageId, element) => {
  if (element) {
    stageNameInputs.set(stageId, element);
    return;
  }

  stageNameInputs.delete(stageId);
};
const updateStageNameDraft = ({ stageId, value }) => {
  stageNames.value = {
    ...stageNames.value,
    [stageId]: value,
  };
};

const updateStageColorDraft = ({ stageId, value }) => {
  stageColors.value = {
    ...stageColors.value,
    [stageId]: value,
  };
};

const startEditingStage = stage => {
  editingStageId.value = stage.id;
  stageNames.value = {
    ...stageNames.value,
    [stage.id]: stage.name,
  };
  stageColors.value = {
    ...stageColors.value,
    [stage.id]: stage.color,
  };
  nextTick(() => stageNameInputs.get(stage.id)?.focus());
};

const openStageDraft = () => {
  isCreatingStageDraft.value = true;
  nextTick(() => {
    newStageNameInput.value?.focus();
    if (boardScrollContainer.value) {
      boardScrollContainer.value.scrollLeft =
        boardScrollContainer.value.scrollWidth;
    }
  });
};

const cancelStageDraft = () => {
  isCreatingStageDraft.value = false;
  newStageName.value = '';
  newStageColor.value = defaultStageColor;
};

const createStage = async () => {
  const name = newStageName.value.trim();
  if (!selectedBoard.value?.id || isCreatingStage.value) return;
  if (!name) {
    useAlert(t('KANBAN.ACTIONS.STAGE_NAME_REQUIRED'));
    nextTick(() => newStageNameInput.value?.focus());
    return;
  }

  isCreatingStage.value = true;

  try {
    const response = await KanbanBoardsAPI.createStage(selectedBoard.value.id, {
      stage: {
        name,
        color: newStageColor.value,
        position: stages.value.length,
      },
    });
    cancelStageDraft();
    pendingScrollToStageId.value = normalizePayload(response.data).id;
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.CREATE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
  } finally {
    isCreatingStage.value = false;
  }
};

const cancelEditingStage = () => {
  const stageId = editingStageId.value;
  editingStageId.value = null;
  if (!stageId) return;
  const { [stageId]: _name, ...restNames } = stageNames.value;
  const { [stageId]: _color, ...restColors } = stageColors.value;
  stageNames.value = restNames;
  stageColors.value = restColors;
};

const updateStage = async stage => {
  const name = String(stageNames.value[stage.id] || '').trim();
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;
  if (!name) {
    useAlert(t('KANBAN.ACTIONS.STAGE_NAME_REQUIRED'));
    nextTick(() => stageNameInputs.get(stage.id)?.focus());
    return;
  }

  startAction(actionKey);

  try {
    const stagePayload = { name };
    if (!isTerminalStage(stage)) {
      stagePayload.color = stageColors.value[stage.id] || defaultStageColor;
    }

    await KanbanBoardsAPI.updateStage(selectedBoard.value.id, stage.id, {
      stage: stagePayload,
    });
    cancelEditingStage();
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.UPDATE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.UPDATE_STAGE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const stageCardCount = stage =>
  stage?.cardsCount ?? stage?.cards_count ?? stage?.cards?.length ?? 0;

const openRemoveStageConfirmation = stage => {
  stagePendingRemoval.value = stage;
  showRemoveStageConfirmation.value = true;
};

const closeRemoveStageConfirmation = () => {
  showRemoveStageConfirmation.value = false;
  stagePendingRemoval.value = null;
};

const removeStage = async stage => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.deleteStage(selectedBoard.value.id, stage.id);
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const confirmRemoveStage = async () => {
  const stage = stagePendingRemoval.value;
  closeRemoveStageConfirmation();

  if (!stage) return;

  await removeStage(stage);
};

const copyStage = async (stage, { name }) => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    const response = await KanbanBoardsAPI.copyStage(
      selectedBoard.value.id,
      stage.id,
      {
        stage: { name },
      }
    );
    pendingScrollToStageId.value = normalizePayload(response.data).id;
    await refreshSelectedBoard();
    useAlert(t('KANBAN.STAGE_MENU.SUCCESS.COPY'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const moveStage = async (stage, { kanbanBoardId, position }) => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.moveStage(selectedBoard.value.id, stage.id, {
      target_kanban_board_id: kanbanBoardId,
      position,
    });
    await Promise.all([
      refreshSelectedBoard(),
      store.dispatch('kanbanBoards/fetchBoards'),
    ]);
    useAlert(t('KANBAN.STAGE_MENU.SUCCESS.MOVE'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const sortStageCards = async (stage, { sortBy }) => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.sortStageCards(selectedBoard.value.id, stage.id, {
      sort_by: sortBy,
    });
    await refreshStageFirstPages([stage.id]);
    useAlert(t('KANBAN.STAGE_MENU.SUCCESS.SORT'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const moveAllStageCards = async (stage, { targetStageId }) => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.moveAllStageCards(selectedBoard.value.id, stage.id, {
      target_stage_id: targetStageId,
    });
    await refreshStageFirstPages([stage.id, targetStageId]);
    useAlert(t('KANBAN.STAGE_MENU.SUCCESS.MOVE_CARDS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const openRemoveStageCardsConfirmation = stage => {
  stageCardsPendingRemoval.value = stage;
  showRemoveStageCardsConfirmation.value = true;
};

const closeRemoveStageCardsConfirmation = () => {
  showRemoveStageCardsConfirmation.value = false;
  stageCardsPendingRemoval.value = null;
};

const removeAllStageCards = async stage => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.deleteAllStageCards(selectedBoard.value.id, stage.id);
    await refreshStageFirstPages([stage.id]);
    useAlert(t('KANBAN.STAGE_MENU.SUCCESS.DELETE_CARDS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const confirmRemoveStageCards = async () => {
  const stage = stageCardsPendingRemoval.value;
  closeRemoveStageCardsConfirmation();

  if (!stage) return;

  await removeAllStageCards(stage);
};

const closeAddItemPicker = () => {
  activeAddItemStageId.value = null;
  showDiscardAddItemConfirm.value = false;
};

const toggleAddItemPicker = stage => {
  if (activeAddItemStageId.value === stage.id) {
    closeAddItemPicker();
    return;
  }

  activeAddItemStageId.value = stage.id;
};

const attemptCloseAddItemPicker = () => {
  if (addItemPickerRef.value?.hasUnsavedChanges) {
    showDiscardAddItemConfirm.value = true;
    return;
  }

  closeAddItemPicker();
};

const keepEditingAddItem = () => {
  showDiscardAddItemConfirm.value = false;
};

const highlightCreatedCard = cardId => {
  if (!cardId) return;

  clearTimeout(createdCardHighlightTimer);
  highlightedCreatedCardId.value = cardId;
  createdCardHighlightTimer = setTimeout(() => {
    highlightedCreatedCardId.value = null;
  }, 2000);
};

const onManualCardCreated = async card => {
  const stageId = card?.kanbanStageId || activeAddItemStageId.value;
  closeAddItemPicker();
  useAlert(t('KANBAN.ADD_ITEM.CREATE_SUCCESS'));

  try {
    await refreshStageFirstPage(stageId);
    highlightCreatedCard(card?.id);
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.LOAD_CARDS_ERROR'));
  }
};

const reorderStageByPosition = async (stage, position) => {
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.reorderStage(selectedBoard.value.id, stage.id, {
      position,
    });
    await refreshSelectedBoard();
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
    await refreshSelectedBoard();
  } finally {
    endAction(actionKey);
  }
};

const onStageDragEnd = async event => {
  stopBoardAutoScroll();
  const stageId = Number(event?.item?.dataset?.stageId);
  const newIndex = event?.newIndex;
  const oldIndex = event?.oldIndex;
  if (!stageId || oldIndex === newIndex || newIndex === undefined) return;

  const stage = stages.value.find(item => item.id === stageId);
  if (!stage) return;

  await reorderStageByPosition(stage, newIndex + 1);
};

const patchCardById = async cardId => {
  const generation = requestGeneration.value;
  const boardId = selectedBoard.value?.id;
  if (!boardId) return;
  const localStageId = findCardStageId({ id: cardId });

  try {
    const response = await KanbanBoardsAPI.showCardById(boardId, cardId);
    if (
      generation !== requestGeneration.value ||
      selectedBoard.value?.id !== boardId
    ) {
      return;
    }
    const card = normalizePayload(response.data);
    const updatedStageId = findCardStageId(card);

    if (card.active === false || !patchVisibleCard(card)) {
      await refreshStageFirstPages([localStageId, updatedStageId]);
    }
  } catch {
    if (
      generation !== requestGeneration.value ||
      selectedBoard.value?.id !== boardId
    ) {
      return;
    }
    await refreshStageFirstPage(localStageId);
  }
};

// Beyond this many buffered cards, refreshing whole stages costs less than
// fetching each card on its own.
const MAX_INDIVIDUAL_CARDS = 5;

const applyRealtimeFlush = async ({
  board,
  stageIds,
  cardIds,
  cardStageIds,
}) => {
  if (!selectedBoard.value?.id) return;
  if (board) {
    await refreshSelectedBoard();
    return;
  }

  if (cardIds.length > MAX_INDIVIDUAL_CARDS) {
    await refreshStageFirstPages([
      ...stageIds,
      ...cardStageIds,
      ...cardIds.map(cardId => findCardStageId({ id: cardId })),
    ]);
    return;
  }

  if (stageIds.length) await refreshStageFirstPages(stageIds);
  await Promise.all(cardIds.map(patchCardById));
};

const realtimeBuffer = useKanbanRealtimeBuffer({
  onFlush: applyRealtimeFlush,
});

const processRealtimeKanbanEvent = (event, data) => {
  if (boardRefreshEvents.has(event)) {
    realtimeBuffer.push({ board: true });
    return;
  }

  if (event === 'kanban.card.created' || event === 'kanban.card.deleted') {
    realtimeBuffer.push({ stageIds: [data.stage_id] });
    return;
  }

  if (event === 'kanban.card.reordered') {
    realtimeBuffer.push({
      stageIds: [data.source_stage_id, data.target_stage_id],
    });
    return;
  }

  if (event === 'kanban.card.updated') {
    if (hasActiveFilters.value) {
      realtimeBuffer.push({
        stageIds: [data.stage_id, findCardStageId({ id: data.card_id })],
      });
      return;
    }

    realtimeBuffer.push({
      cardIds: [data.card_id],
      cardStageIds: [data.stage_id],
    });
  }
};

const flushPendingRealtimeKanbanEvents = () => {
  if (!pendingRealtimeKanbanEvents.value.length) return;

  const events = pendingRealtimeKanbanEvents.value;
  pendingRealtimeKanbanEvents.value = [];

  events.forEach(({ event, data }) => {
    if (!selectedBoard.value?.id || data?.board_id !== selectedBoard.value.id) {
      return;
    }

    processRealtimeKanbanEvent(event, data);
  });
};

const handleRealtimeKanbanEvent = ({ event, data } = {}) => {
  if (!selectedBoard.value?.id || data?.board_id !== selectedBoard.value.id) {
    return;
  }

  if (isCardDragging.value) {
    pendingRealtimeKanbanEvents.value.push({ event, data });
    return;
  }

  processRealtimeKanbanEvent(event, data);
};

const onCardDragStart = () => {
  isCardDragging.value = true;
  hasCardDragChanged.value = false;
  startBoardAutoScroll();
};

const onCardDragChange = async (stage, event) => {
  if (event?.added || event?.moved || event?.removed) {
    hasCardDragChanged.value = true;
  }

  const card = event?.added?.element || event?.moved?.element;
  const targetIndex = event?.added?.newIndex ?? event?.moved?.newIndex;
  if (
    !selectedBoard.value?.id ||
    !stage?.id ||
    !card ||
    targetIndex === undefined ||
    isPersistingCardDrag.value
  ) {
    return;
  }

  // Dropping on the last loaded slot while more cards exist beyond the
  // page means the true end of the stage isn't known locally, so the
  // position is omitted and the backend appends the card to the real end.
  const isLastLoadedSlot = targetIndex === stage.cards.length - 1;
  const appendsToStageEnd = isLastLoadedSlot && !!stage.pagination?.hasMore;
  const destinationPosition = appendsToStageEnd ? undefined : targetIndex + 1;
  const stageChanged = card.kanbanStageId !== stage.id;
  const positionChanged =
    appendsToStageEnd || card.position !== destinationPosition;
  if (!stageChanged && !positionChanged) return;

  const actionKey = cardActionKey(card);
  if (isActionActive(actionKey)) return;

  isPersistingCardDrag.value = true;
  startAction(actionKey);
  const payload = {
    card: {
      kanban_stage_id: stage.id,
      ...(appendsToStageEnd ? {} : { position: destinationPosition }),
    },
  };

  try {
    await KanbanBoardsAPI.reorderCardById(
      selectedBoard.value.id,
      card.id,
      payload
    );
    await refreshStageFirstPages([card.kanbanStageId, stage.id]);
  } catch (error) {
    let message = getErrorMessage(
      error,
      t('KANBAN.ACTIONS.REORDER_CARD_ERROR')
    );
    if (isLostReasonRequiredError(error)) {
      message = t('KANBAN.ACTIONS.DRAG_LOST_REASON_REQUIRED');
    }
    if (isDirectWonLostTransitionError(error)) {
      message = t('KANBAN.ACTIONS.DRAG_DIRECT_WON_LOST_TRANSITION_NOT_ALLOWED');
    }

    useAlert(message);
    await refreshStageFirstPages([card.kanbanStageId, stage.id]);
  } finally {
    isPersistingCardDrag.value = false;
    endAction(actionKey);
  }
};

const onCardDragEnd = () => {
  stopBoardAutoScroll();
  if (isCardDragging.value || hasCardDragChanged.value) {
    suppressNextCardClick.value = true;
    window.setTimeout(() => {
      suppressNextCardClick.value = false;
    }, 0);
  }

  isCardDragging.value = false;
  hasCardDragChanged.value = false;
  flushPendingRealtimeKanbanEvents();
};

const openRemoveCardConfirmation = card => {
  cardPendingRemoval.value = card;
  showRemoveCardConfirmation.value = true;
};

const closeRemoveCardConfirmation = () => {
  showRemoveCardConfirmation.value = false;
  cardPendingRemoval.value = null;
};

const removeCard = async card => {
  const actionKey = cardActionKey(card);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.deleteCardById(selectedBoard.value.id, card.id);
    await refreshStageFirstPage(findCardStageId(card));
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const confirmRemoveCard = async () => {
  const card = cardPendingRemoval.value;
  closeRemoveCardConfirmation();

  if (!card) return;

  await removeCard(card);
};

const updateCardPriority = async (card, priorityValue) => {
  const actionKey = cardActionKey(card);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.updateCardDetailsById(
      selectedBoard.value.id,
      card.id,
      { priority: priorityValue || null }
    );
    patchVisibleCard({ id: card.id, card_priority: priorityValue });
  } catch (error) {
    showActionError(error, t('KANBAN.CARD.PRIORITY_UPDATE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const moveCardToStage = async (card, targetStageId) => {
  const targetStage = stages.value.find(
    stage => Number(stage.id) === Number(targetStageId)
  );
  const actionKey = cardActionKey(card);
  if (
    !selectedBoard.value?.id ||
    !targetStage ||
    isTerminalStage(targetStage) ||
    isActionActive(actionKey)
  ) {
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.reorderCardById(selectedBoard.value.id, card.id, {
      card: {
        kanban_stage_id: targetStage.id,
        after_card_id: null,
      },
    });
    await refreshStageFirstPages([card.kanbanStageId, targetStage.id]);
    useAlert(t('KANBAN.CARD.MOVE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const assignAgent = async (card, userId) => {
  const actionKey = cardActionKey(card);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

  const numericUserId = Number(userId);
  const currentAssigneeIds = (card.assignees || []).map(assignee =>
    Number(assignee.id)
  );
  const nextAssigneeIds = currentAssigneeIds.includes(numericUserId)
    ? currentAssigneeIds.filter(id => id !== numericUserId)
    : [...currentAssigneeIds, numericUserId];

  startAction(actionKey);

  try {
    const response = await KanbanBoardsAPI.updateCardAssignees(
      selectedBoard.value.id,
      card.id,
      nextAssigneeIds
    );
    patchVisibleCard({
      id: card.id,
      kanbanStageId: card.kanbanStageId,
      assignees: normalizePayload(response.data.payload),
    });
    useAlert(t('KANBAN.CARD.ASSIGN_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.CARD.ASSIGN_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const updateCardDueDate = async (card, dueDate) => {
  const actionKey = cardActionKey(card);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

  const dueAt = toIso8601(dueDate);
  startAction(actionKey);

  try {
    await KanbanBoardsAPI.updateCardDetailsById(
      selectedBoard.value.id,
      card.id,
      { due_at: dueAt }
    );
    patchVisibleCard({
      id: card.id,
      kanbanStageId: card.kanbanStageId,
      due_at: dueAt,
    });
    useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.CARD.DUE_DATE_UPDATE_ERROR'));
  } finally {
    endAction(actionKey);
  }
};

const onChangeCardStatus = async (
  card,
  { targetStageId, reasonId, reopen }
) => {
  const actionKey = cardActionKey(card);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

  startAction(actionKey);

  try {
    const response = reopen
      ? await KanbanBoardsAPI.reopenCardById(selectedBoard.value.id, card.id)
      : await KanbanBoardsAPI.updateCardById(selectedBoard.value.id, card.id, {
          card: {
            kanban_stage_id: targetStageId,
            kanban_reason_id: reasonId || null,
          },
        });
    const updatedCard = normalizePayload(response.data);
    const nextStageId = updatedCard.kanbanStageId || targetStageId;
    await refreshStageFirstPages([card.kanbanStageId, nextStageId]);
    useAlert(
      t(
        reopen
          ? 'KANBAN.CARD.STATUS.REOPEN_SUCCESS'
          : 'KANBAN.CARD.STATUS.UPDATE_SUCCESS'
      )
    );
  } catch (error) {
    useAlert(
      getCardStatusChangeErrorMessage(error, { reopen, t, getErrorMessage })
    );
  } finally {
    endAction(actionKey);
  }
};

const cancelBoardRename = () => {
  renamingBoardId.value = null;
  renameValue.value = '';
};

const startBoardRename = board => {
  renamingBoardId.value = board.id;
  renameValue.value = board.name || '';
};

const confirmBoardRename = async () => {
  const board = boards.value.find(item => item.id === renamingBoardId.value);
  const name = renameValue.value.trim();
  if (!board || !name || isRenamingBoard.value) return;

  if (name === board.name) {
    cancelBoardRename();
    return;
  }

  isRenamingBoard.value = true;
  try {
    await KanbanBoardsAPI.update(board.id, { kanban_board: { name } });
    await store.dispatch('kanbanBoards/refreshBoards');
    // The header title reads from selectedBoard, which is loaded by showBoard
    // rather than from the board list, so patch it instead of refetching.
    if (selectedBoard.value?.id === board.id) selectedBoard.value.name = name;
    cancelBoardRename();
  } catch (error) {
    // Keep the row in edit mode so the name can be corrected in place, most
    // commonly after the per-account uniqueness check rejects a duplicate.
    useAlert(getErrorMessage(error, t('KANBAN.ACTIONS.RENAME_BOARD_ERROR')));
  } finally {
    isRenamingBoard.value = false;
  }
};

const closeBoardDropdown = () => {
  isBoardDropdownOpen.value = false;
  cancelBoardRename();
};
const toggleBoardDropdown = () => {
  isBoardDropdownOpen.value = hasBoards.value && !isBoardDropdownOpen.value;
};

const goToOverview = () => {
  router.push({
    name: 'kanban_boards',
    params: { accountId: route.params.accountId },
  });
};

const selectBoard = boardId => {
  if (boardId === activeBoardId.value) return;

  closeBoardDropdown();
  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
  });
};

const goToCreateBoard = () => {
  closeBoardDropdown();
  router.push({
    name: 'kanban_board_create_form',
    params: { accountId: route.params.accountId },
  });
};

const fetchBoards = async () => {
  hasError.value = false;

  try {
    await Promise.all([
      store.dispatch('kanbanBoards/fetchBoards'),
      inboxes.value.length ? Promise.resolve() : store.dispatch('inboxes/get'),
      agents.value.length ? Promise.resolve() : store.dispatch('agents/get'),
      store.dispatch('labels/get'),
    ]);

    const nextBoardId = activeBoardId.value || boards.value[0]?.id;
    if (nextBoardId && !activeBoardId.value) {
      router.replace({
        name: 'kanban_board_show',
        params: {
          accountId: route.params.accountId,
          boardId: nextBoardId,
        },
      });
      return;
    }

    if (nextBoardId) {
      await showBoardWithSnapshot(nextBoardId);
    }
  } catch {
    hasError.value = true;
    selectedBoard.value = null;
  }
};

const getContactName = card =>
  card.contact?.name ||
  card.conversation?.meta?.sender?.name ||
  t('KANBAN.CARD.UNKNOWN_CONTACT');

const removeCardMessageValue = computed(() => {
  if (!cardPendingRemoval.value) return '';

  return getContactName(cardPendingRemoval.value);
});
const removeStageMessageValue = computed(() => {
  if (!stagePendingRemoval.value) return '';

  return `${stagePendingRemoval.value.name} (${t(
    'KANBAN.STAGE_MENU.CARD_COUNT',
    { count: stageCardCount(stagePendingRemoval.value) }
  )})`;
});
const removeStageCardsMessageValue = computed(() => {
  if (!stageCardsPendingRemoval.value) return '';

  return `${stageCardsPendingRemoval.value.name} (${t(
    'KANBAN.STAGE_MENU.CARD_COUNT',
    { count: stageCardCount(stageCardsPendingRemoval.value) }
  )})`;
});

const openConversationInNewTab = card => {
  if (!card?.conversationId) return;

  // A standalone tab opens the conversation on its own inbox route rather than
  // the board-embedded one. The board stays mounted in this tab and the new tab
  // gets its own sessionStorage, so there is no snapshot to save here.
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: card.conversationId,
    })
  );
  window.open(
    `${window.chatwootConfig.hostURL}${path}`,
    '_blank',
    'noopener,noreferrer'
  );
};

const openConversation = (card, event = {}) => {
  if (!card?.conversationId) return;

  if (suppressNextCardClick.value) {
    suppressNextCardClick.value = false;
    return;
  }

  if (event.metaKey || event.ctrlKey) {
    openConversationInNewTab(card);
    return;
  }

  saveBoardSnapshot();
  pushEmbedded(router, {
    name: 'kanban_board_conversation',
    params: {
      accountId: route.params.accountId,
      boardId: selectedBoard.value.id,
      conversationId: card.conversationId,
    },
  });
};

const openDetails = card => {
  if (suppressNextCardClick.value) {
    suppressNextCardClick.value = false;
    return;
  }

  selectedOpportunityCardId.value = card.id;
};

const closeOpportunityDetails = () => {
  selectedOpportunityCardId.value = null;
  showUnsavedOpportunityChangesConfirm.value = false;
};

const attemptCloseOpportunityDetails = () => {
  if (opportunityModalRef.value?.hasUnsavedChanges) {
    showUnsavedOpportunityChangesConfirm.value = true;
    return;
  }

  closeOpportunityDetails();
};

const keepEditingOpportunity = () => {
  showUnsavedOpportunityChangesConfirm.value = false;
};

const discardOpportunityChanges = () => {
  closeOpportunityDetails();
};

const saveAndCloseOpportunity = async () => {
  if (isSavingOpportunityBeforeExit.value) return;

  isSavingOpportunityBeforeExit.value = true;

  try {
    const saved = await opportunityModalRef.value?.saveCard();
    if (saved) closeOpportunityDetails();
  } finally {
    isSavingOpportunityBeforeExit.value = false;
  }
};

const onOpportunityUpdated = updatedCard => {
  if (hasActiveFilters.value) {
    const originStageId = findCardStageId({
      id: selectedOpportunityCardId.value,
    });
    const destinationStageId = updatedCard?.kanbanStageId;
    refreshStageFirstPages([originStageId, destinationStageId]);
    return;
  }
  if (patchVisibleCard(updatedCard)) return;

  refreshStageFirstPage(
    findCardStageId({
      id: selectedOpportunityCardId.value,
      kanbanStageId: updatedCard?.kanbanStageId,
    })
  );
};

const onOpportunityRemoveCard = card => {
  closeOpportunityDetails();
  openRemoveCardConfirmation(card);
};

watch(activeBoardId, (boardId, previousBoardId) => {
  if (!boards.value.length) return;

  if (previousBoardId && previousBoardId !== boardId) {
    boardFilters.value = emptyBoardFilters();
    selectedBoard.value = null;
    searchRequestToken += 1;
    requestGeneration.value += 1;
    clearSearchDebounce();
    searchInput.value = '';
    activeSearchTerm.value = '';
    preSearchScrollLeft.value = null;
  }

  closeBoardDropdown();
  showBoardWithSnapshot(
    boardId,
    !(previousBoardId && previousBoardId !== boardId)
  );
});

onMounted(() => {
  emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
  fetchBoards();
});

onUnmounted(() => {
  clearTimeout(createdCardHighlightTimer);
  stopBoardAutoScroll();
  cancelEditingStage();
  cancelStageDraft();
  emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
});

watch(searchInput, () => {
  scheduleSearch(runSearch);
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <section class="flex min-w-0 flex-1 flex-col">
      <KanbanBoardHeader
        v-model:rename-value="renameValue"
        v-model:search-input="searchInput"
        :boards="boards"
        :has-boards="hasBoards"
        :selected-board="selectedBoard"
        :active-board-id="activeBoardId"
        :current-board-name="currentBoardName"
        :is-board-dropdown-open="isBoardDropdownOpen"
        :renaming-board-id="renamingBoardId"
        :is-renaming-board="isRenamingBoard"
        :is-admin="isAdmin"
        :is-search-loading="isSearchLoading"
        :is-mine-active="isMineActive"
        :is-today-active="isTodayActive"
        :today-cards-count="todayCardsCount"
        :board-filters="boardFilters"
        :inbox-filter-options="inboxFilterOptions"
        :agent-filter-options="agentFilterOptions"
        :active-board-filter-count="activeBoardFilterCount"
        :has-active-board-filters="hasActiveBoardFilters"
        :is-creating-stage="isCreatingStage"
        @go-to-overview="goToOverview"
        @close-board-dropdown="closeBoardDropdown"
        @toggle-board-dropdown="toggleBoardDropdown"
        @start-board-rename="startBoardRename"
        @confirm-board-rename="confirmBoardRename"
        @cancel-board-rename="cancelBoardRename"
        @select-board="selectBoard"
        @go-to-create-board="goToCreateBoard"
        @search-keydown="onSearchKeydown"
        @toggle-mine="toggleMine"
        @toggle-today="toggleToday"
        @update-board-filters="updateBoardFilters"
        @clear-board-filters="clearBoardFilters"
        @open-board-settings="openBoardSettings"
        @open-stage-draft="openStageDraft"
      />

      <div
        v-if="hasError"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-ruby-11"
      >
        {{ t('KANBAN.ERROR') }}
      </div>

      <div
        v-else-if="isInitialLoading || (isFetchingBoard && !selectedBoard)"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.LOADING_BOARD') }}
      </div>

      <div
        v-else-if="!hasBoards"
        class="flex flex-1 items-center justify-center p-6 text-center"
      >
        <div class="max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.EMPTY_BOARDS') }}
          </h3>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('KANBAN.EMPTY_BOARDS_DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div
        v-else-if="hasBoards && stages.length === 0 && !isCreatingStageDraft"
        class="flex flex-1 items-center justify-center p-6 text-center"
      >
        <div class="max-w-md">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.EMPTY_STAGES') }}
          </h3>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('KANBAN.EMPTY_STAGES_DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div
        v-else-if="hasBoards && (stages.length > 0 || isCreatingStageDraft)"
        class="flex min-h-0 flex-1 flex-col"
      >
        <div
          v-if="selectedBoard && hasNoSearchResults"
          class="mx-4 mt-4 flex items-center justify-between gap-3 rounded-lg border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.SEARCH.NO_RESULTS', { term: activeSearchTerm }) }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ t('KANBAN.SEARCH.NO_RESULTS_DESCRIPTION') }}
            </p>
          </div>
          <button
            type="button"
            class="flex-shrink-0 rounded-md px-2 py-1 text-sm font-medium text-n-brand hover:bg-n-alpha-2"
            :aria-label="t('KANBAN.SEARCH.CLEAR')"
            @click="clearSearch"
          >
            {{ t('KANBAN.SEARCH.CLEAR') }}
          </button>
        </div>

        <div
          ref="boardScrollContainer"
          class="flex min-h-0 flex-1 overflow-x-auto p-4"
          :class="[
            isDraggingBoard
              ? 'snap-none'
              : 'snap-x snap-mandatory lg:snap-none',
            isReloadingBoard
              ? 'opacity-60 pointer-events-none transition-opacity'
              : 'transition-opacity',
          ]"
        >
          <Draggable
            v-model="stageListModel"
            item-key="id"
            class="flex min-h-0 gap-4"
            handle=".stage-drag-handle"
            :filter="interactiveDragFilter"
            :prevent-on-filter="false"
            :move="canMoveStage"
            v-bind="sortableFallbackOptions"
            ghost-class="opacity-60"
            chosen-class="opacity-90"
            :animation="150"
            @start="startBoardAutoScroll"
            @end="onStageDragEnd"
          >
            <template #item="{ element: stage }">
              <KanbanStageColumn
                :stage="stage"
                :board="selectedBoard"
                :stages="stages"
                :boards="boards"
                :is-admin="isAdmin"
                :is-busy="isActionActive(stageActionKey(stage))"
                :is-card-drag-disabled="isCardDragDisabled"
                :has-active-filters="hasActiveFilters"
                :highlighted-card-id="highlightedCreatedCardId"
                :sortable-options="sortableFallbackOptions"
                :cards-error="getStageCardsError(stage.id)"
                :is-loading-cards="isStageCardsLoading(stage.id)"
                :assignable-users="assignableUsers"
                :interactive-drag-filter="interactiveDragFilter"
                :is-card-busy="isCardBusy"
                :is-terminal-stage="isTerminalStage"
                :stage-accent="stageAccent"
                :can-add-card-in-empty-stage="canAddCardInEmptyStage"
                :can-add-card-in-stage-footer="canAddCardInStageFooter"
                :empty-cards-label="emptyCardsLabel"
                :editing-stage-id="editingStageId"
                :stage-names="stageNames"
                :stage-colors="stageColors"
                :set-stage-name-input="setStageNameInput"
                @update-stage-name="updateStageNameDraft"
                @update-stage-color="updateStageColorDraft"
                @add-card="toggleAddItemPicker"
                @edit-stage="startEditingStage"
                @update-stage="updateStage"
                @cancel-editing-stage="cancelEditingStage"
                @copy-stage="copyStage"
                @move-stage="moveStage"
                @move-all-cards="moveAllStageCards"
                @sort-cards="sortStageCards"
                @delete-stage="openRemoveStageConfirmation"
                @delete-all-cards="openRemoveStageCardsConfirmation"
                @open-card="openDetails"
                @open-conversation="openConversation"
                @open-conversation-in-new-tab="openConversationInNewTab"
                @remove-card="openRemoveCardConfirmation"
                @update-priority="updateCardPriority"
                @change-status="onChangeCardStatus"
                @move-card-to-stage="moveCardToStage"
                @assign-agent="assignAgent"
                @update-due-date="updateCardDueDate"
                @load-more="loadMoreStageCards"
                @drag-start="onCardDragStart"
                @drag-change="onCardDragChange"
                @drag-end="onCardDragEnd"
              />
            </template>
          </Draggable>
          <button
            v-if="!isCreatingStageDraft"
            type="button"
            data-testid="kanban-create-stage-draft"
            class="flex w-64 lg:w-80 flex-shrink-0 snap-start items-center justify-center gap-2 rounded-lg border border-dashed border-n-weak px-3 py-6 text-sm font-medium text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1 hover:text-n-brand"
            :aria-label="t('KANBAN.ACTIONS.CREATE_STAGE_DRAFT')"
            @click="openStageDraft"
          >
            <i class="i-lucide-plus size-4" />
            {{ t('KANBAN.ACTIONS.CREATE_STAGE_DRAFT') }}
          </button>
          <KanbanStageDraft
            v-else
            ref="newStageNameInput"
            v-model:new-stage-name="newStageName"
            v-model:new-stage-color="newStageColor"
            :is-creating-stage="isCreatingStage"
            @create-stage="createStage"
            @cancel-stage-draft="cancelStageDraft"
          />
        </div>
      </div>
    </section>

    <woot-delete-modal
      v-model:show="showRemoveCardConfirmation"
      :on-close="closeRemoveCardConfirmation"
      :on-confirm="confirmRemoveCard"
      :title="t('KANBAN.REMOVE_CARD.TITLE')"
      :message="t('KANBAN.REMOVE_CARD.MESSAGE')"
      :message-value="removeCardMessageValue"
      :confirm-text="t('KANBAN.REMOVE_CARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_CARD.CANCEL')"
    />
    <woot-delete-modal
      v-model:show="showRemoveStageConfirmation"
      :on-close="closeRemoveStageConfirmation"
      :on-confirm="confirmRemoveStage"
      :title="t('KANBAN.STAGE_MENU.DELETE_STAGE_CONFIRM.TITLE')"
      :message="t('KANBAN.STAGE_MENU.DELETE_STAGE_CONFIRM.MESSAGE')"
      :message-value="removeStageMessageValue"
      :confirm-text="t('KANBAN.STAGE_MENU.DELETE_STAGE_CONFIRM.CONFIRM')"
      :reject-text="t('KANBAN.STAGE_MENU.DELETE_STAGE_CONFIRM.CANCEL')"
    />
    <woot-delete-modal
      v-model:show="showRemoveStageCardsConfirmation"
      :on-close="closeRemoveStageCardsConfirmation"
      :on-confirm="confirmRemoveStageCards"
      :title="t('KANBAN.STAGE_MENU.DELETE_CARDS_CONFIRM.TITLE')"
      :message="t('KANBAN.STAGE_MENU.DELETE_CARDS_CONFIRM.MESSAGE')"
      :message-value="removeStageCardsMessageValue"
      :confirm-text="t('KANBAN.STAGE_MENU.DELETE_CARDS_CONFIRM.CONFIRM')"
      :reject-text="t('KANBAN.STAGE_MENU.DELETE_CARDS_CONFIRM.CANCEL')"
    />

    <woot-modal
      v-if="selectedOpportunityCardId && selectedBoard"
      :show="!!selectedOpportunityCardId"
      :show-close-button="false"
      size="modal-fit-content"
      :on-close="attemptCloseOpportunityDetails"
    >
      <KanbanOpportunityDetailsModal
        ref="opportunityModalRef"
        :board-id="selectedBoard.id"
        :card-id="selectedOpportunityCardId"
        :won-stage-id="selectedBoard.wonStageId"
        :lost-stage-id="selectedBoard.lostStageId"
        :lost-reason-required="!!selectedBoard.lostReasonRequired"
        :reasons="selectedBoard.reasons || []"
        :custom-fields="selectedBoard.customFields || []"
        @close="attemptCloseOpportunityDetails"
        @updated="onOpportunityUpdated"
        @open-conversation="openConversation"
        @remove-card="onOpportunityRemoveCard"
      />
    </woot-modal>

    <woot-modal
      :show="showUnsavedOpportunityChangesConfirm"
      :show-close-button="false"
      size="modal-narrow"
      :on-close="keepEditingOpportunity"
    >
      <div class="p-6">
        <h2 class="mb-2 text-base font-semibold text-n-slate-12">
          {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_TITLE') }}
        </h2>
        <p class="mb-6 text-sm text-n-slate-11">
          {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_MESSAGE') }}
        </p>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <NextButton
            outline
            slate
            sm
            :label="t('KANBAN.OPPORTUNITY_DETAILS.KEEP_EDITING')"
            @click="keepEditingOpportunity"
          />
          <NextButton
            ruby
            sm
            :label="t('KANBAN.OPPORTUNITY_DETAILS.DISCARD_CHANGES')"
            @click="discardOpportunityChanges"
          />
          <NextButton
            sm
            :is-loading="isSavingOpportunityBeforeExit"
            :label="t('KANBAN.OPPORTUNITY_DETAILS.SAVE_AND_EXIT')"
            @click="saveAndCloseOpportunity"
          />
        </div>
      </div>
    </woot-modal>

    <woot-modal
      v-if="activeAddItemStageId && selectedBoard"
      :show="!!activeAddItemStageId"
      :show-close-button="false"
      size="modal-narrow"
      :on-close="attemptCloseAddItemPicker"
    >
      <KanbanOpportunityPicker
        ref="addItemPickerRef"
        :kanban-board-id="selectedBoard.id"
        :kanban-stage-id="activeAddItemStageId"
        :kanban-stage-name="activeAddItemStage?.name"
        :inbox-scope-mode="selectedBoard.inboxScopeMode"
        :allowed-inbox-ids="selectedBoard.allowedInboxIds"
        @created="onManualCardCreated"
        @close="attemptCloseAddItemPicker"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDiscardAddItemConfirm"
      :on-close="keepEditingAddItem"
      :on-confirm="closeAddItemPicker"
      :title="t('KANBAN.ADD_ITEM.DISCARD_TITLE')"
      :message="t('KANBAN.ADD_ITEM.DISCARD_CONFIRM')"
      :confirm-text="t('KANBAN.ADD_ITEM.DISCARD')"
      :reject-text="t('KANBAN.ADD_ITEM.KEEP_EDITING')"
    />
  </main>
</template>
