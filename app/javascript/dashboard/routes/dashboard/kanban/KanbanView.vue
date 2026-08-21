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
import { useKanbanStageActions } from 'dashboard/composables/useKanbanStageActions';
import { useKanbanCardActions } from 'dashboard/composables/useKanbanCardActions';
import { useKanbanCardSelection } from 'dashboard/composables/useKanbanCardSelection';
import { useKanbanBulkActions } from 'dashboard/composables/useKanbanBulkActions';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import KanbanStageColumn from './board/KanbanStageColumn.vue';
import KanbanBoardHeader from './board/KanbanBoardHeader.vue';
import KanbanBoardSummary from './board/KanbanBoardSummary.vue';
import KanbanStageDraft from './board/KanbanStageDraft.vue';
import KanbanBulkActions from './KanbanBulkActions.vue';
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
import {
  ALL_TIME_TERMINAL_PERIOD,
  normalizeTerminalPeriod,
} from 'dashboard/helper/kanbanBoardFilters';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import KanbanOpportunityPanel from './opportunity/KanbanOpportunityPanel.vue';
import KanbanOpportunityPicker from './KanbanOpportunityPicker.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();

const currentUserId = useMapGetter('getCurrentUserID');
const agents = useMapGetter('agents/getAgents');
const boards = useMapGetter('kanbanBoards/kanbanBoards');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const labels = useMapGetter('labels/getLabels');
const isFetchingBoards = useMapGetter('kanbanBoards/kanbanBoardsLoading');
const { isAdmin } = useAdmin();
const selectedBoard = ref(null);
const collapsedStageIds = ref(new Set());
const isSummaryCollapsed = ref(false);
const isFetchingBoard = ref(false);
const isCreatingStage = ref(false);
const isCreatingStageDraft = ref(false);
const selectedOpportunityCardId = ref(null);
const opportunityModalRef = ref(null);
const opportunityTriggerRef = ref(null);
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
const stagePendingMove = ref(null);
const showRemoveCardConfirmation = ref(false);
const showRemoveStageConfirmation = ref(false);
const showRemoveStageCardsConfirmation = ref(false);
const showMoveStageConfirmation = ref(false);
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
} = useKanbanBoardFiltersState({
  currentUserId,
  isFetchingBoard,
  stages,
});
const isStageCollapsed = stageId => collapsedStageIds.value.has(stageId);
const terminalPeriodOptions = computed(() => [
  { value: '7d', label: t('KANBAN.STAGE.PERIOD.7D') },
  { value: '30d', label: t('KANBAN.STAGE.PERIOD.30D') },
  { value: '90d', label: t('KANBAN.STAGE.PERIOD.90D') },
  { value: ALL_TIME_TERMINAL_PERIOD, label: t('KANBAN.STAGE.PERIOD.ALL') },
]);
const {
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
} = useKanbanBoardData({
  collapsedStageIds,
  currentFilterParams,
  hasError,
  isFetchingBoard,
  route,
  router,
  selectedBoard,
  stages,
  t,
});
// The server owns the cap; the board payload carries it so the two cannot drift.
const selectionLimit = computed(() => selectedBoard.value?.bulkActionLimit);
const {
  clearCardSelection,
  isSelectionMode,
  selectedCardIds,
  selectedCards,
  toggleCardSelection,
} = useKanbanCardSelection({
  findCardStage,
  selectionLimit,
  stages,
  t,
  useAlert,
});
const hasAssignedSelectedCards = computed(() =>
  selectedCards.value.some(card => card.assignees?.length)
);
const hasLabeledSelectedCards = computed(() =>
  selectedCards.value.some(card => card.labels?.length)
);
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
  () => isPersistingCardDrag.value || isBoardBusy.value
);
const canAddCardInEmptyStage = stage =>
  !isTerminalStage(stage) && !hasActiveFilters.value && !isCardDragging.value;
const canAddCardInStageFooter = stage =>
  !isTerminalStage(stage) && stage.cards.length > 0;
const isTerminalStagePeriodFiltered = stage =>
  isTerminalStage(stage) && terminalPeriod.value !== ALL_TIME_TERMINAL_PERIOD;
const emptyCardsLabel = stage =>
  hasActiveFilters.value || isTerminalStagePeriodFiltered(stage)
    ? t('KANBAN.EMPTY_CARDS_FILTERED')
    : t('KANBAN.EMPTY_CARDS');

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

const stageCardsBlockedMessage = error => {
  const blocked = error?.response?.data?.blocked || {};
  const duplicateCount = Number(blocked.card_already_in_target_board || 0);
  const inboxCount = Number(blocked.inbox_not_allowed || 0);
  const count = duplicateCount + inboxCount;
  const details = [
    duplicateCount
      ? t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED_DUPLICATE', {
          count: duplicateCount,
        })
      : null,
    inboxCount
      ? t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED_INBOX', {
          count: inboxCount,
        })
      : null,
  ].filter(Boolean);

  return [
    t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED', { count }),
    ...details,
  ].join(' ');
};

const stageActionErrorMessage = error => {
  switch (error?.response?.data?.error) {
    case 'stage_not_empty':
      return t('KANBAN.STAGE_MENU.ERRORS.STAGE_NOT_EMPTY');
    case 'stage_cards_blocked':
      return stageCardsBlockedMessage(error);
    case 'stage_name_taken':
      return t('KANBAN.STAGE_MENU.ERRORS.STAGE_NAME_TAKEN');
    case 'last_stage_cannot_move_board':
      return t('KANBAN.STAGE_MENU.ERRORS.LAST_STAGE_CANNOT_MOVE_BOARD');
    case 'special_stage_cannot_move_board':
      return t('KANBAN.STAGE_MENU.ERRORS.SPECIAL_STAGE_CANNOT_MOVE_BOARD');
    case 'special_stage_cannot_be_deleted':
      return t('KANBAN.ACTIONS.REMOVE_STAGE_TERMINAL');
    case 'terminal_stage_not_allowed':
      return t('KANBAN.STAGE_MENU.ERRORS.TERMINAL_STAGE_NOT_ALLOWED');
    case 'bulk_action_limit_exceeded':
      return t('KANBAN.STAGE_MENU.ERRORS.MOVE_CARDS_LIMIT', {
        count: selectionLimit.value,
      });
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

const boardPrefsUserId = () => currentUserId.value ?? 'unknown';

const loadBoardPrefs = boardId => {
  const prefs = getKanbanBoardPrefs({
    accountId: route.params.accountId,
    boardId,
    userId: boardPrefsUserId(),
  });
  const storedStageIds = Array.isArray(prefs?.collapsedStageIds)
    ? prefs.collapsedStageIds.map(Number).filter(Boolean)
    : [];

  collapsedStageIds.value = new Set(storedStageIds);
  terminalPeriod.value = normalizeTerminalPeriod(prefs?.terminalPeriod);
  isSummaryCollapsed.value = prefs?.summaryCollapsed === true;

  return prefs;
};

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

      if (isStageCollapsed(stage.id)) return;

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
  const prefs = loadBoardPrefs(boardId);
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

// Every stored preference is derived from live board state, so persisting is
// always a full snapshot taken after that state has been updated.
const persistBoardPrefs = () => {
  if (!selectedBoard.value?.id) return;

  saveKanbanBoardPrefs({
    accountId: route.params.accountId,
    boardId: selectedBoard.value.id,
    userId: boardPrefsUserId(),
    prefs: {
      collapsedStageIds: [...collapsedStageIds.value],
      terminalPeriod: terminalPeriod.value,
      summaryCollapsed: isSummaryCollapsed.value,
      mine: isMineActive.value,
      today: isTodayActive.value,
    },
  });
};

const toggleStageCollapsed = async stage => {
  if (!stage?.id) return;

  const nextCollapsedStageIds = new Set(collapsedStageIds.value);
  if (nextCollapsedStageIds.has(stage.id)) {
    nextCollapsedStageIds.delete(stage.id);
  } else {
    nextCollapsedStageIds.add(stage.id);
  }

  collapsedStageIds.value = nextCollapsedStageIds;
  persistBoardPrefs();

  // Collapsing drops the cards and keeps the counters, expanding brings the
  // cards back; both are the same first-page refresh.
  await refreshStageFirstPage(stage.id);
};

const updateTerminalPeriod = async ({ stageId, value }) => {
  terminalPeriod.value = normalizeTerminalPeriod(value);
  persistBoardPrefs();
  await refreshStageFirstPage(stageId);
};

const updateBoardFilters = async filters => {
  boardFilters.value = normalizeBoardFilters(filters);
  persistBoardPrefs();
  requestGeneration.value += 1;
  await refreshSelectedBoard();
};

const toggleSummary = () => {
  isSummaryCollapsed.value = !isSummaryCollapsed.value;
  persistBoardPrefs();
};

const clearBoardFilters = () => {
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

const {
  cancelEditingStage,
  cancelStageDraft,
  closeMoveStageConfirmation,
  closeRemoveStageCardsConfirmation,
  closeRemoveStageConfirmation,
  confirmMoveStage,
  confirmRemoveStage,
  confirmRemoveStageCards,
  copyStage,
  createStage,
  moveAllStageCards,
  moveStage,
  onStageDragEnd,
  openRemoveStageCardsConfirmation,
  openRemoveStageConfirmation,
  openStageDraft,
  setStageNameInput,
  sortStageCards,
  stageCardCount,
  startEditingStage,
  updateStage,
  updateStageColorDraft,
  updateStageNameDraft,
} = useKanbanStageActions({
  boardScrollContainer,
  boards,
  defaultStageColor,
  editingStageId,
  endAction,
  isActionActive,
  isCreatingStage,
  isCreatingStageDraft,
  isTerminalStage,
  newStageColor,
  newStageName,
  newStageNameInput,
  normalizePayload,
  pendingScrollToStageId,
  refreshSelectedBoard,
  refreshStageFirstPages,
  selectedBoard,
  showMoveStageConfirmation,
  showActionError,
  showRemoveStageCardsConfirmation,
  showRemoveStageConfirmation,
  stageActionKey,
  stageCardsPendingRemoval,
  stagePendingMove,
  stageColors,
  stageNames,
  stageNameInputs,
  stagePendingRemoval,
  stages,
  startAction,
  stopBoardAutoScroll,
  store,
  t,
  useAlert,
});

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

const {
  assignAgent,
  closeRemoveCardConfirmation,
  confirmRemoveCard,
  moveCardToBoard,
  moveCardToStage,
  onCardDragChange,
  onCardDragEnd,
  onCardDragStart,
  onChangeCardStatus,
  openRemoveCardConfirmation,
  updateCardDueDate,
  updateCardLabels,
  updateCardPriority,
} = useKanbanCardActions({
  boards,
  cardActionKey,
  cardPendingRemoval,
  endAction,
  findCardStageId,
  flushPendingRealtimeKanbanEvents,
  getErrorMessage,
  hasActiveFilters,
  hasCardDragChanged,
  isActionActive,
  isCardDragging,
  isLostReasonRequiredError,
  isPersistingCardDrag,
  isTerminalStage,
  normalizePayload,
  patchVisibleCard,
  refreshStageFirstPage,
  refreshStageFirstPages,
  selectedBoard,
  showActionError,
  showRemoveCardConfirmation,
  stages,
  startAction,
  startBoardAutoScroll,
  stopBoardAutoScroll,
  suppressNextCardClick,
  t,
  toIso8601,
  useAlert,
});

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
const moveStageTargetBoard = computed(() => {
  const targetBoardId = stagePendingMove.value?.kanbanBoardId;
  return boards.value.find(board => Number(board.id) === Number(targetBoardId));
});
const moveStageDroppedFieldKeys = computed(() => {
  if (!stagePendingMove.value) return [];

  const sourceFields = selectedBoard.value?.customFields || [];
  const targetFields = moveStageTargetBoard.value?.customFields || [];

  return sourceFields
    .filter(
      sourceField =>
        !targetFields.some(
          targetField =>
            targetField.key === sourceField.key &&
            targetField.fieldType === sourceField.fieldType &&
            Boolean(targetField.multiple) === Boolean(sourceField.multiple)
        )
    )
    .map(field => field.key)
    .filter(Boolean);
});
const moveStageConfirmationMessage = computed(() => {
  const pendingMove = stagePendingMove.value;
  if (!pendingMove) return '';

  return t('KANBAN.STAGE_MENU.MOVE.CONFIRM_MESSAGE', {
    count: stageCardCount(pendingMove.stage),
  });
});
const moveStageConfirmationDroppedFields = computed(() => {
  if (!moveStageDroppedFieldKeys.value.length) return '';

  return ` ${t('KANBAN.STAGE_MENU.MOVE.CONFIRM_DROPPED_FIELDS', {
    fields: moveStageDroppedFieldKeys.value.join(', '),
  })}`;
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

  const cardElement = document.querySelector(`[data-card-id="${card.id}"]`);
  const activeElement = document.activeElement;
  opportunityTriggerRef.value =
    cardElement ||
    (activeElement && activeElement !== document.body ? activeElement : null);
  selectedOpportunityCardId.value = card.id;
};

const closeOpportunityDetails = () => {
  selectedOpportunityCardId.value = null;
  showUnsavedOpportunityChangesConfirm.value = false;
  nextTick(() => {
    opportunityTriggerRef.value?.focus?.();
    opportunityTriggerRef.value = null;
  });
};

const openCardFromQuery = () => {
  const cardId = Number(route.query?.card_id);
  if (!selectedBoard.value || !Number.isInteger(cardId) || cardId <= 0) {
    return;
  }

  openDetails({ id: cardId });
  router.replace({ query: { ...route.query, card_id: undefined } });
};

watch([selectedBoard, () => route.query?.card_id], openCardFromQuery);

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

const {
  applyBulkAction,
  closeBulkDeleteConfirmation,
  confirmBulkDelete,
  openBulkDeleteConfirmation,
  showBulkDeleteConfirmation,
} = useKanbanBulkActions({
  clearCardSelection,
  endAction,
  findCardStageId,
  getErrorMessage,
  isBoardBusy,
  refreshStageFirstPages,
  selectedBoard,
  selectedCardIds,
  selectionLimit,
  startAction,
  store,
  t,
  useAlert,
});

watch(isFetchingBoard, isFetching => {
  if (isFetching) clearCardSelection();
});

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

      <KanbanBoardSummary
        v-if="selectedBoard"
        :summary="boardSummary"
        :is-loading="isFetchingSummary"
        :error="summaryError"
        :is-collapsed="isSummaryCollapsed"
        @toggle="toggleSummary"
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
          class="flex min-h-0 flex-1 overflow-x-auto p-4 [&::-webkit-scrollbar]:h-2 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-thumb]:bg-n-alpha-3 [&::-webkit-scrollbar-track]:bg-transparent"
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
                :collapsed="isStageCollapsed(stage.id)"
                :terminal-period="terminalPeriod"
                :terminal-period-options="terminalPeriodOptions"
                :board="selectedBoard"
                :stages="stages"
                :boards="boards"
                :is-admin="isAdmin"
                :is-busy="isActionActive(stageActionKey(stage))"
                :is-card-drag-disabled="isCardDragDisabled"
                :selected-card-ids="selectedCardIds"
                :is-selection-mode="isSelectionMode"
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
                :empty-cards-label="emptyCardsLabel(stage)"
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
                @move-card-to-board="moveCardToBoard"
                @assign-agent="assignAgent"
                @update-due-date="updateCardDueDate"
                @update-labels="updateCardLabels"
                @toggle-select="toggleCardSelection"
                @load-more="loadMoreStageCards"
                @drag-start="onCardDragStart"
                @drag-change="onCardDragChange"
                @drag-end="onCardDragEnd"
                @toggle-collapse="toggleStageCollapsed(stage)"
                @update-terminal-period="updateTerminalPeriod"
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

    <KanbanBulkActions
      v-if="selectedBoard && selectedCardIds.size"
      :selected-count="selectedCardIds.size"
      :board="selectedBoard"
      :boards="boards"
      :stages="stages"
      :assignable-users="assignableUsers"
      :has-assigned-selected-cards="hasAssignedSelectedCards"
      :has-labeled-selected-cards="hasLabeledSelectedCards"
      :labels="labels"
      :reasons="selectedBoard.reasons || []"
      :won-stage-id="selectedBoard.wonStageId"
      :lost-stage-id="selectedBoard.lostStageId"
      :lost-reason-required="!!selectedBoard.lostReasonRequired"
      :is-busy="isBoardBusy"
      @action="applyBulkAction"
      @delete="openBulkDeleteConfirmation"
      @clear="clearCardSelection"
    />

    <woot-delete-modal
      v-model:show="showMoveStageConfirmation"
      :on-close="closeMoveStageConfirmation"
      :on-confirm="confirmMoveStage"
      :is-loading="isBoardBusy"
      :title="t('KANBAN.STAGE_MENU.MOVE.CONFIRM_TITLE')"
      :message="moveStageConfirmationMessage"
      :message-value="moveStageConfirmationDroppedFields"
      :confirm-text="t('KANBAN.STAGE_MENU.MOVE.CONFIRM_SUBMIT')"
      :reject-text="t('KANBAN.STAGE_MENU.MOVE.CONFIRM_CANCEL')"
    />

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
      v-model:show="showBulkDeleteConfirmation"
      :on-close="closeBulkDeleteConfirmation"
      :on-confirm="confirmBulkDelete"
      :is-loading="isBoardBusy"
      :title="t('KANBAN.BULK.DELETE_CONFIRM_TITLE')"
      :message="
        t('KANBAN.BULK.DELETE_CONFIRM_MESSAGE', {
          count: selectedCardIds.size,
        })
      "
      :confirm-text="t('KANBAN.BULK.DELETE')"
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

    <KanbanOpportunityPanel
      v-if="selectedOpportunityCardId && selectedBoard"
      ref="opportunityModalRef"
      :board-id="selectedBoard.id"
      :card-id="selectedOpportunityCardId"
      :stages="selectedBoard.stages || []"
      :won-stage-id="selectedBoard.wonStageId"
      :lost-stage-id="selectedBoard.lostStageId"
      :lost-reason-required="!!selectedBoard.lostReasonRequired"
      :reasons="selectedBoard.reasons || []"
      :custom-fields="selectedBoard.customFields || []"
      :move-to-stage="moveCardToStage"
      :has-blocking-dialog="showUnsavedOpportunityChangesConfirm"
      @close="attemptCloseOpportunityDetails"
      @updated="onOpportunityUpdated"
      @open-conversation="openConversation"
      @remove-card="onOpportunityRemoveCard"
    />

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
          {{
            t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_FIELDS_MESSAGE', {
              fields: opportunityModalRef?.unsavedFields?.join(', '),
            })
          }}
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
