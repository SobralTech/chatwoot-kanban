<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import KanbanFilterMenu from './KanbanFilterMenu.vue';
import KanbanStageMenu from './KanbanStageMenu.vue';
import { frontendURL, kanbanConversationUrl } from 'dashboard/helper/URLHelper';
import { pushEmbedded } from 'dashboard/helper/embeddedConversationHistory';
import {
  getKanbanBoardSnapshot,
  removeKanbanBoardSnapshot,
  saveKanbanBoardSnapshot,
} from 'dashboard/helper/kanbanBoardSnapshot';
import { applyMatchModeConstraints } from 'dashboard/helper/kanbanBoardFilters';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import KanbanConversationCard from './KanbanConversationCard.vue';
import KanbanOpportunityDetailsModal from './KanbanOpportunityDetailsModal.vue';
import KanbanOpportunityPicker from './KanbanOpportunityPicker.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const store = useStore();

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
const activeActionKeys = ref(new Set());
const startAction = key => {
  activeActionKeys.value = new Set(activeActionKeys.value).add(key);
};
const endAction = key => {
  const next = new Set(activeActionKeys.value);
  next.delete(key);
  activeActionKeys.value = next;
};
const isActionActive = key => activeActionKeys.value.has(key);
const isBoardBusy = computed(() => activeActionKeys.value.size > 0);
const stageActionKey = stage => `stage-${stage.id}`;
const cardActionKey = (action, card) => `${action}-${card.id}`;
const isCardBusy = (card, stage) =>
  [
    cardActionKey('reorder-card', card),
    cardActionKey('change-status', card),
    cardActionKey('remove-card', card),
    stageActionKey(stage),
  ].some(isActionActive);
const hasError = ref(false);
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
const stageCardsLoading = ref({});
const stageCardsErrors = ref({});
const stageRefreshRequests = new Map();
const stageDataVersions = new Map();
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
const pendingScrollToStageId = ref(null);
const searchInput = ref('');
const activeSearchTerm = ref('');
let searchDebounceTimer = null;
let searchRequestToken = 0;
const preSearchScrollLeft = ref(null);
let requestGeneration = 0;
const staleRequest = Symbol('stale-kanban-request');

// Auto-scroll while dragging. SortableJS runs in fallback mode (see the card
// and stage Draggable options), so the pointer keeps emitting events during a
// drag and we can drive both axes ourselves: the board scrolls horizontally
// and the column under the pointer scrolls vertically.
const AUTO_SCROLL_EDGE = 120;
const AUTO_SCROLL_MAX_SPEED = 24;
let dragPointerX = -1;
let dragPointerY = -1;
let dragPointerReady = false;
let autoScrollRaf = null;

const onDragPointerMove = e => {
  dragPointerX = e.clientX;
  dragPointerY = e.clientY;
  dragPointerReady = true;
};

// Ramps from 0 at the edge threshold up to AUTO_SCROLL_MAX_SPEED at the very
// border, so the board eases in instead of jumping at a fixed speed.
const edgeScrollDelta = (position, start, end) => {
  if (position < start + AUTO_SCROLL_EDGE) {
    const intensity = (start + AUTO_SCROLL_EDGE - position) / AUTO_SCROLL_EDGE;
    return -AUTO_SCROLL_MAX_SPEED * Math.min(intensity, 1);
  }
  if (position > end - AUTO_SCROLL_EDGE) {
    const intensity = (position - (end - AUTO_SCROLL_EDGE)) / AUTO_SCROLL_EDGE;
    return AUTO_SCROLL_MAX_SPEED * Math.min(intensity, 1);
  }
  return 0;
};

const runBoardAutoScroll = () => {
  const board = boardScrollContainer.value;
  if (board && dragPointerReady) {
    const boardRect = board.getBoundingClientRect();
    const dx = edgeScrollDelta(dragPointerX, boardRect.left, boardRect.right);
    if (dx) {
      board.scrollLeft = Math.max(
        0,
        Math.min(board.scrollLeft + dx, board.scrollWidth - board.clientWidth)
      );
    }

    // Sortable's fallback clone is pointer-events: none, so this resolves to
    // the column actually under the cursor.
    const column = document
      .elementFromPoint(dragPointerX, dragPointerY)
      ?.closest('[data-stage-scroll-id]');
    if (column) {
      const columnRect = column.getBoundingClientRect();
      const dy = edgeScrollDelta(
        dragPointerY,
        columnRect.top,
        columnRect.bottom
      );
      if (dy) {
        column.scrollTop = Math.max(
          0,
          Math.min(
            column.scrollTop + dy,
            column.scrollHeight - column.clientHeight
          )
        );
      }
    }
  }
  autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
};

const startBoardAutoScroll = () => {
  if (autoScrollRaf) return;
  dragPointerReady = false;
  dragPointerX = -1;
  dragPointerY = -1;
  document.addEventListener('pointermove', onDragPointerMove);
  autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
};

const stopBoardAutoScroll = () => {
  document.removeEventListener('pointermove', onDragPointerMove);
  if (autoScrollRaf) cancelAnimationFrame(autoScrollRaf);
  autoScrollRaf = null;
  dragPointerReady = false;
};
// vuedraggable forwards unknown attributes straight to SortableJS as options,
// so these have to be real booleans: written as bare attributes they resolve to
// "" and silently leave the native HTML5 drag backend in place, which emits no
// pointer events and therefore no auto-scroll. Sortable's own scroll plugin is
// off because runBoardAutoScroll drives both axes.
const sortableFallbackOptions = {
  forceFallback: true,
  fallbackOnBody: true,
  scroll: false,
};
const interactiveDragFilter =
  'button,a,input,textarea,select,[contenteditable="true"],.no-drag';
const stageCardsPageLimit = 20;
const boardRefreshEvents = new Set([
  'kanban.board.updated',
  'kanban.stage.created',
  'kanban.stage.updated',
  'kanban.stage.deleted',
  'kanban.stage.reordered',
]);

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const stages = computed(() => selectedBoard.value?.stages || []);
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
const stageListModel = computed({
  get: () => selectedBoard.value?.stages || [],
  set: nextStages => {
    if (!selectedBoard.value) return;

    selectedBoard.value = { ...selectedBoard.value, stages: nextStages };
  },
});
const { isTerminalStage, canMoveStage } = useKanbanStageOrder({
  stages,
  wonStageId: computed(() => selectedBoard.value?.wonStageId),
  lostStageId: computed(() => selectedBoard.value?.lostStageId),
});
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
const hasActiveBoardFilters = computed(() => activeBoardFilterCount.value > 0);
const hasActiveFilters = computed(
  () => hasActiveBoardFilters.value || activeSearchTerm.value.length >= 2
);
const isSearchLoading = computed(
  () => isFetchingBoard.value && searchInput.value !== ''
);
const isCardDragDisabled = computed(
  () => isPersistingCardDrag.value || isBoardBusy.value
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
const currentFilterParams = () => ({
  ...currentBoardFilterParams(),
  ...currentSearchParams(),
});
const currentBoardRequestConfig = () =>
  Object.keys(currentFilterParams()).length > 0
    ? { params: currentFilterParams() }
    : undefined;

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

const isRefreshRequiredError = error =>
  error?.response?.status === 409 &&
  error?.response?.data?.error === 'refresh_required';

const isLostReasonRequiredError = error =>
  error?.response?.data?.error === 'lost_reason_required';

const formatCurrency = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(value) || 0);

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
  generation = requestGeneration
) => {
  const response = await KanbanBoardsAPI.getStageCards(
    selectedBoard.value.id,
    stageId,
    {
      ...params,
      ...currentFilterParams(),
    }
  );

  if (generation !== requestGeneration) return staleRequest;
  return normalizeKanbanPayload(response.data);
};

const reloadStageCards = async (stageId, generation = requestGeneration) => {
  const stage = stages.value.find(item => item.id === stageId);
  const limit = Math.max(stageCardsPageLimit, stage?.cards?.length || 0);

  const page = await fetchStageCardsPage(stageId, { limit }, generation);
  if (page === staleRequest) return false;
  applyStageFirstPage(stageId, page);
  return true;
};

const refreshStageFirstPage = (stageId, generation = requestGeneration) => {
  if (!selectedBoard.value?.id || !stageId) return Promise.resolve();

  const requestKey = `${generation}:${stageId}`;
  if (stageRefreshRequests.has(requestKey)) {
    return stageRefreshRequests.get(requestKey);
  }

  const request = reloadStageCards(stageId, generation).finally(() => {
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

const findCardStageId = card => {
  if (card?.kanbanStageId) return card.kanbanStageId;

  return stages.value.find(stage =>
    stage.cards.some(item => item.id === card?.id)
  )?.id;
};

const patchVisibleCard = card => {
  const updatedCard = normalizePayload(card);
  if (!updatedCard?.id) return false;

  const stageId = findCardStageId(updatedCard);
  if (
    !stageId ||
    (updatedCard.kanbanStageId && updatedCard.kanbanStageId !== stageId)
  ) {
    return false;
  }

  updateStageCards(stageId, stage => ({
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
  if (!selectedBoard.value?.id || !stage?.id || isStageCardsLoading(stage.id)) {
    return;
  }

  const stageId = stage.id;
  const generation = requestGeneration;
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
      generation !== requestGeneration ||
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

    if (generation === requestGeneration) {
      setStageCardsError(stageId, t('KANBAN.ACTIONS.LOAD_CARDS_ERROR'));
    }
  } finally {
    if (generation === requestGeneration) setStageCardsLoading(stageId, false);
  }
};

const showBoard = async (boardId, generation = requestGeneration) => {
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
    if (generation !== requestGeneration) return;
    stageCardsLoading.value = {};
    stageCardsErrors.value = {};
    selectedBoard.value = normalizeKanbanPayload(response.data);
  } catch (error) {
    if (generation !== requestGeneration) return;
    hasError.value = true;
    if ([403, 404].includes(error?.response?.status)) {
      router.replace({
        name: 'kanban_boards',
        params: { accountId: route.params.accountId },
      });
    }
  } finally {
    if (generation === requestGeneration) isFetchingBoard.value = false;
  }
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
  if (generation !== requestGeneration || selectedBoard.value?.id !== boardId) {
    return;
  }

  // showBoard already loaded every stage's first page, so only the stages
  // that had been paged past it need to be re-fetched.
  await Promise.all(
    stages.value.map(async stage => {
      if (
        generation !== requestGeneration ||
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
        generation !== requestGeneration ||
        selectedBoard.value?.id !== boardId
      ) {
        return;
      }
      applyStageFirstPage(stage.id, page);
    })
  );

  if (generation !== requestGeneration || selectedBoard.value?.id !== boardId) {
    return;
  }
  await nextTick();

  if (generation !== requestGeneration || selectedBoard.value?.id !== boardId) {
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
  const generation = requestGeneration;
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

  if (generation !== requestGeneration) return;
  await showBoard(boardId, generation);
  if (generation !== requestGeneration || selectedBoard.value?.id !== boardId) {
    return;
  }

  await applyBoardSnapshot(snapshot, boardId, generation);
  if (generation !== requestGeneration || selectedBoard.value?.id !== boardId) {
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

  const generation = requestGeneration;
  await showBoard(selectedBoard.value.id, generation);
  if (generation !== requestGeneration) return;
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
  requestGeneration += 1;
  const token = searchRequestToken;
  if (!activeSearchTerm.value && nextTerm) {
    preSearchScrollLeft.value = boardScrollContainer.value?.scrollLeft ?? 0;
  }
  activeSearchTerm.value = nextTerm;
  const generation = requestGeneration;
  await refreshSelectedBoard();
  if (token !== searchRequestToken || generation !== requestGeneration) return;
  if (nextTerm) await scrollToFirstMatchingStage();
  else if (generation === requestGeneration) restorePreSearchScroll();
};

const clearSearch = () => {
  searchInput.value = '';
};
const onSearchKeydown = event => {
  if (event.key !== 'Escape' || searchInput.value === '') return;
  event.preventDefault();
  clearSearch();
};
const searchResultCount = computed(() =>
  stages.value.reduce((total, stage) => total + (stage.cardsCount || 0), 0)
);
const hasNoSearchResults = computed(
  () => activeSearchTerm.value.length >= 2 && searchResultCount.value === 0
);

const updateBoardFilters = async filters => {
  boardFilters.value = normalizeBoardFilters(filters);
  requestGeneration += 1;
  await refreshSelectedBoard();
};

const clearBoardFilters = () => updateBoardFilters(emptyBoardFilters());

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
  const color = stageColors.value[stage.id] || defaultStageColor;
  const actionKey = stageActionKey(stage);
  if (!selectedBoard.value?.id || isActionActive(actionKey)) return;
  if (!name) {
    useAlert(t('KANBAN.ACTIONS.STAGE_NAME_REQUIRED'));
    nextTick(() => stageNameInputs.get(stage.id)?.focus());
    return;
  }

  startAction(actionKey);

  try {
    await KanbanBoardsAPI.updateStage(selectedBoard.value.id, stage.id, {
      stage: {
        name,
        color,
      },
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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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
  if (!selectedBoard.value?.id || !stage?.id) return;
  const actionKey = stageActionKey(stage);
  if (isActionActive(actionKey)) return;

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

const handleRealtimeCardUpdated = async data => {
  if (Object.keys(currentFilterParams()).length > 0) {
    const localStageId = stages.value.find(stage =>
      stage.cards.some(card => card.id === data.card_id)
    )?.id;
    await refreshStageFirstPages([data.stage_id, localStageId]);
    return;
  }

  const generation = requestGeneration;
  const boardId = selectedBoard.value?.id;
  if (!boardId) return;

  try {
    const response = await KanbanBoardsAPI.showCardById(boardId, data.card_id);
    if (
      generation !== requestGeneration ||
      selectedBoard.value?.id !== boardId
    ) {
      return;
    }
    const card = normalizePayload(response.data);

    if (card.active === false || !patchVisibleCard(card)) {
      await refreshStageFirstPage(data.stage_id);
    }
  } catch {
    if (
      generation !== requestGeneration ||
      selectedBoard.value?.id !== boardId
    ) {
      return;
    }
    await refreshStageFirstPage(data.stage_id);
  }
};

const processRealtimeKanbanEvent = (event, data) => {
  if (boardRefreshEvents.has(event)) {
    refreshSelectedBoard();
    return;
  }

  if (event === 'kanban.card.created' || event === 'kanban.card.deleted') {
    refreshStageFirstPage(data.stage_id);
    return;
  }

  if (event === 'kanban.card.reordered') {
    if (data.source_stage_id === data.target_stage_id) {
      refreshStageFirstPage(data.source_stage_id);
      return;
    }

    refreshStageFirstPages([data.source_stage_id, data.target_stage_id]);
    return;
  }

  if (event === 'kanban.card.updated') {
    handleRealtimeCardUpdated(data);
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
  const positionChanged = hasActiveFilters.value
    ? stageChanged || event?.moved?.oldIndex !== event?.moved?.newIndex
    : appendsToStageEnd || card.position !== destinationPosition;
  if (!stageChanged && !positionChanged) return;

  const actionKey = cardActionKey('reorder-card', card);
  if (isActionActive(actionKey)) return;

  isPersistingCardDrag.value = true;
  startAction(actionKey);
  const anchorCard = targetIndex > 0 ? stage.cards[targetIndex - 1] : null;
  const cardPayload = { kanban_stage_id: stage.id };
  if (hasActiveFilters.value) {
    cardPayload.after_card_id = anchorCard?.id ?? null;
  } else if (!appendsToStageEnd) {
    cardPayload.position = destinationPosition;
  }
  const payload = { card: cardPayload };

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
  const actionKey = cardActionKey('remove-card', card);
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
  if (!selectedBoard.value?.id) return;

  try {
    await KanbanBoardsAPI.updateCardDetailsById(
      selectedBoard.value.id,
      card.id,
      { priority: priorityValue || null }
    );
    patchVisibleCard({ id: card.id, card_priority: priorityValue });
  } catch (error) {
    showActionError(error, t('KANBAN.CARD.PRIORITY_UPDATE_ERROR'));
  }
};

const onChangeCardStatus = async (
  card,
  { targetStageId, reasonId, reopen }
) => {
  const actionKey = cardActionKey('change-status', card);
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

const getConversationPath = card =>
  frontendURL(
    kanbanConversationUrl({
      accountId: route.params.accountId,
      boardId: selectedBoard.value.id,
      conversationId: card.conversationId,
    })
  );

const openConversationInNewTab = card => {
  if (!card?.conversationId) return;

  // The board stays mounted in this tab and the new tab gets its own
  // sessionStorage, so there is no snapshot to save here.
  window.open(
    `${window.chatwootConfig.hostURL}${getConversationPath(card)}`,
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
    requestGeneration += 1;
    clearTimeout(searchDebounceTimer);
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
  clearTimeout(searchDebounceTimer);
  clearTimeout(createdCardHighlightTimer);
  stopBoardAutoScroll();
  cancelEditingStage();
  cancelStageDraft();
  emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
});

watch(searchInput, () => {
  clearTimeout(searchDebounceTimer);
  searchDebounceTimer = setTimeout(runSearch, 350);
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <section class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex min-h-16 flex-wrap items-center justify-between gap-2 border-b border-n-weak px-4 py-3 md:px-6"
      >
        <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1">
          <NextButton
            data-testid="kanban-back-to-overview"
            icon="i-lucide-chevron-left"
            variant="ghost"
            color="slate"
            size="md"
            class="flex-shrink-0 [&>span]:size-5"
            :aria-label="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
            :title="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
            @click="goToOverview"
          />
          <OnClickOutside @trigger="closeBoardDropdown">
            <div class="relative inline-flex min-w-0 max-w-full flex-col">
              <button
                type="button"
                data-testid="kanban-board-switcher"
                class="inline-flex min-w-0 max-w-full items-center gap-2 rounded-md px-1 py-1 text-left text-base font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="!hasBoards"
                @click="isBoardDropdownOpen = hasBoards && !isBoardDropdownOpen"
              >
                <span class="min-w-0 truncate">{{ currentBoardName }}</span>
                <i
                  class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11 transition-transform"
                  :class="{ 'rotate-180': isBoardDropdownOpen }"
                />
              </button>
              <div
                v-if="isBoardDropdownOpen"
                data-testid="kanban-board-switcher-dropdown"
                class="absolute left-0 top-full z-50 mt-2 w-96 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border-0 bg-n-alpha-3 shadow-lg outline outline-1 outline-n-container backdrop-blur-[100px]"
              >
                <div class="max-h-80 overflow-y-auto">
                  <div
                    v-for="board in boards"
                    :key="board.id"
                    class="group flex w-full items-center gap-2 px-4 py-3 text-sm text-n-slate-12 hover:bg-n-alpha-1"
                  >
                    <template v-if="renamingBoardId === board.id">
                      <InlineInput
                        v-model="renameValue"
                        focus-on-mount
                        data-testid="kanban-board-rename-input"
                        :placeholder="t('KANBAN.ACTIONS.RENAME_BOARD')"
                        class="min-w-0 flex-1"
                        @enter-press="confirmBoardRename"
                        @escape-press="cancelBoardRename"
                      />
                      <NextButton
                        icon="i-lucide-check"
                        ghost
                        xs
                        slate
                        data-testid="kanban-board-rename-confirm"
                        :is-loading="isRenamingBoard"
                        :disabled="isRenamingBoard"
                        :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD_CONFIRM')"
                        :title="t('KANBAN.ACTIONS.RENAME_BOARD_CONFIRM')"
                        @click="confirmBoardRename"
                      />
                      <NextButton
                        icon="i-lucide-x"
                        ghost
                        xs
                        slate
                        :disabled="isRenamingBoard"
                        :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD_CANCEL')"
                        :title="t('KANBAN.ACTIONS.RENAME_BOARD_CANCEL')"
                        @click="cancelBoardRename"
                      />
                    </template>
                    <template v-else>
                      <button
                        type="button"
                        class="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-left"
                        :title="board.name"
                        @click="selectBoard(board.id)"
                      >
                        {{ board.name }}
                      </button>
                      <NextButton
                        v-if="isAdmin"
                        icon="i-lucide-pencil"
                        ghost
                        xs
                        slate
                        data-testid="kanban-board-rename-start"
                        class="opacity-0 transition-opacity focus:opacity-100 group-hover:opacity-100"
                        :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD')"
                        :title="t('KANBAN.ACTIONS.RENAME_BOARD')"
                        @click.stop="startBoardRename(board)"
                      />
                      <i
                        v-if="board.id === activeBoardId"
                        class="i-lucide-check size-4 flex-shrink-0 text-n-brand"
                      />
                    </template>
                  </div>
                </div>
                <div class="border-t border-n-weak p-2">
                  <button
                    type="button"
                    class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm font-medium text-n-brand hover:bg-n-alpha-1"
                    data-testid="kanban-board-switcher-create-new"
                    @click="goToCreateBoard"
                  >
                    <i class="i-lucide-plus size-4" />
                    {{ t('KANBAN.OVERVIEW.CREATE_BOARD') }}
                  </button>
                </div>
              </div>
            </div>
          </OnClickOutside>
          <div
            v-if="selectedBoard"
            class="min-w-[9rem] max-w-64 grow basis-36 ltr:ml-2 rtl:mr-2"
          >
            <Input
              v-model="searchInput"
              type="search"
              size="sm"
              class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
              :placeholder="t('KANBAN.SEARCH.PLACEHOLDER')"
              data-testid="kanban-search-input"
              @keydown="onSearchKeydown"
            >
              <template #prefix>
                <Icon
                  :icon="
                    isSearchLoading ? 'i-lucide-loader-2' : 'i-lucide-search'
                  "
                  class="absolute top-1/2 size-3.5 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand ltr:left-2.5 rtl:right-2.5"
                  :class="{ 'animate-spin': isSearchLoading }"
                />
              </template>
            </Input>
          </div>
        </div>
        <div
          class="flex flex-shrink-0 flex-wrap items-center justify-end gap-2"
        >
          <template v-if="selectedBoard">
            <div
              data-testid="kanban-filter-menu-container"
              class="flex items-center overflow-hidden rounded-lg"
              :class="{
                'border border-n-weak bg-n-alpha-1': hasActiveBoardFilters,
              }"
            >
              <KanbanFilterMenu
                :model-value="boardFilters"
                :inbox-options="inboxFilterOptions"
                :agent-options="agentFilterOptions"
                :active-count="activeBoardFilterCount"
                @update:model-value="updateBoardFilters"
              />
              <button
                v-if="hasActiveBoardFilters"
                type="button"
                data-testid="kanban-clear-filters"
                class="h-10 border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 ltr:border-l rtl:border-r"
                @click="clearBoardFilters"
              >
                {{ t('KANBAN.FILTERS.CLEAR_ALL') }}
              </button>
            </div>
            <button
              v-if="isAdmin"
              type="button"
              data-testid="kanban-board-settings-button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
              :title="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
              @click="openBoardSettings"
            >
              <span class="i-lucide-settings size-4" />
            </button>
            <button
              type="button"
              data-testid="kanban-create-stage-toggle"
              class="flex size-10 items-center justify-center rounded-lg bg-n-brand text-white disabled:cursor-not-allowed disabled:opacity-50"
              :aria-label="t('KANBAN.ACTIONS.CREATE_STAGE')"
              :title="t('KANBAN.ACTIONS.CREATE_STAGE')"
              :disabled="isCreatingStage"
              @click="openStageDraft"
            >
              <i class="i-lucide-plus size-4" />
            </button>
          </template>
        </div>
      </header>

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
          :class="
            isReloadingBoard
              ? 'opacity-60 pointer-events-none transition-opacity'
              : 'transition-opacity'
          "
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
              <section
                :data-stage-id="stage.id"
                class="flex w-80 flex-shrink-0 flex-col rounded-lg border border-n-weak bg-n-solid-1"
                :class="
                  editingStageId === stage.id
                    ? 'overflow-visible'
                    : 'overflow-hidden'
                "
              >
                <header
                  class="flex min-h-10 items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
                  :class="
                    editingStageId === stage.id
                      ? ''
                      : 'stage-drag-handle cursor-grab'
                  "
                >
                  <OnClickOutside
                    v-if="editingStageId === stage.id"
                    class="min-w-0 flex-1"
                    @trigger="cancelEditingStage"
                  >
                    <form
                      class="flex min-w-0 w-full items-center gap-2"
                      @submit.prevent="updateStage(stage)"
                    >
                      <ColorPicker
                        v-model="stageColors[stage.id]"
                        preview-only
                        :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
                        data-testid="kanban-stage-color-picker"
                        class="flex-shrink-0"
                      />
                      <input
                        :ref="element => setStageNameInput(stage.id, element)"
                        v-model="stageNames[stage.id]"
                        type="text"
                        class="reset-base !mb-0 h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                        :placeholder="
                          t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')
                        "
                        @keydown.escape.prevent="cancelEditingStage"
                      />
                      <NextButton
                        type="submit"
                        icon="i-lucide-check"
                        ghost
                        xs
                        slate
                        class="no-drag"
                        :aria-label="t('KANBAN.ACTIONS.SAVE_STAGE')"
                        :title="t('KANBAN.ACTIONS.SAVE_STAGE')"
                      />
                      <NextButton
                        icon="i-lucide-x"
                        ghost
                        xs
                        slate
                        class="no-drag"
                        :aria-label="t('KANBAN.ACTIONS.CANCEL')"
                        :title="t('KANBAN.ACTIONS.CANCEL')"
                        @click="cancelEditingStage"
                      />
                    </form>
                  </OnClickOutside>
                  <template v-else>
                    <div class="flex min-w-0 flex-1 items-center gap-2">
                      <span
                        class="size-2.5 flex-shrink-0 rounded-full"
                        :style="{ backgroundColor: stage.color }"
                        aria-hidden="true"
                      />
                      <h3
                        class="truncate text-sm font-semibold text-n-slate-12"
                      >
                        {{ stage.name }}
                      </h3>
                      <span
                        class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                      >
                        {{ stage.cardsCount }}
                      </span>
                      <span
                        v-if="stage.totalValue > 0"
                        data-testid="kanban-stage-total-value"
                        class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                      >
                        {{ formatCurrency(stage.totalValue) }}
                      </span>
                    </div>
                    <div class="flex flex-shrink-0 gap-1">
                      <KanbanStageMenu
                        :stage="stage"
                        :stages="stages"
                        :boards="boards"
                        :won-stage-id="selectedBoard?.wonStageId"
                        :lost-stage-id="selectedBoard?.lostStageId"
                        :is-admin="isAdmin"
                        :is-busy="isActionActive(stageActionKey(stage))"
                        @add-card="toggleAddItemPicker(stage)"
                        @edit="startEditingStage(stage)"
                        @copy="copyStage(stage, $event)"
                        @move="moveStage(stage, $event)"
                        @move-cards="moveAllStageCards(stage, $event)"
                        @sort="sortStageCards(stage, $event)"
                        @delete-stage="openRemoveStageConfirmation(stage)"
                        @delete-cards="openRemoveStageCardsConfirmation(stage)"
                      />
                    </div>
                  </template>
                </header>

                <div
                  :data-stage-scroll-id="stage.id"
                  class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3"
                >
                  <Draggable
                    :list="stage.cards"
                    item-key="id"
                    class="flex flex-1 flex-col gap-2 rounded-md"
                    :title="
                      hasActiveFilters
                        ? t('KANBAN.ACTIONS.REORDER_ANCHORED_HINT')
                        : undefined
                    "
                    :group="{ name: 'kanban-cards' }"
                    handle=".card-drag-handle"
                    :filter="interactiveDragFilter"
                    :prevent-on-filter="false"
                    :empty-insert-threshold="30"
                    :swap-threshold="0.65"
                    :inverted-swap-threshold="1"
                    v-bind="sortableFallbackOptions"
                    :disabled="isCardDragDisabled"
                    ghost-class="opacity-60"
                    chosen-class="opacity-90"
                    :animation="150"
                    @start="onCardDragStart"
                    @change="onCardDragChange(stage, $event)"
                    @end="onCardDragEnd"
                  >
                    <template #item="{ element: card }">
                      <KanbanConversationCard
                        :class="{
                          'ring-2 ring-n-brand':
                            card.id === highlightedCreatedCardId,
                        }"
                        :card="card"
                        :is-busy="isCardBusy(card, stage)"
                        :won-stage-id="selectedBoard?.wonStageId"
                        :lost-stage-id="selectedBoard?.lostStageId"
                        :reasons="selectedBoard?.reasons || []"
                        :lost-reason-required="
                          selectedBoard?.lostReasonRequired
                        "
                        @open-details="openDetails"
                        @open-conversation="openConversation"
                        @remove-card="openRemoveCardConfirmation"
                        @update-priority="updateCardPriority"
                        @change-status="onChangeCardStatus"
                      />
                    </template>
                    <template #footer>
                      <template v-if="stage.cards.length === 0">
                        <button
                          v-if="canAddCardInEmptyStage(stage)"
                          type="button"
                          data-testid="kanban-empty-stage-add-card"
                          :data-stage-id="stage.id"
                          class="flex min-h-24 w-full flex-col items-center justify-center gap-2 rounded-md border border-dashed border-n-weak px-3 py-6 text-sm font-medium text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                          :disabled="isActionActive(stageActionKey(stage))"
                          @click="toggleAddItemPicker(stage)"
                        >
                          <i class="i-lucide-plus size-5" />
                          {{ t('KANBAN.ACTIONS.ADD_FIRST_CARD') }}
                        </button>
                        <p
                          v-else
                          class="pointer-events-none px-1 py-2 text-sm text-n-slate-10"
                        >
                          {{ emptyCardsLabel }}
                        </p>
                      </template>
                    </template>
                  </Draggable>

                  <div
                    v-if="getStageCardsError(stage.id)"
                    class="text-sm text-n-ruby-11"
                  >
                    {{ getStageCardsError(stage.id) }}
                  </div>

                  <button
                    v-if="stage.pagination?.hasMore"
                    type="button"
                    data-testid="kanban-load-more-cards"
                    :data-stage-id="stage.id"
                    class="no-drag flex w-full items-center justify-center gap-1 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:enabled:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                    :disabled="isStageCardsLoading(stage.id)"
                    @click="loadMoreStageCards(stage)"
                  >
                    <i
                      v-if="isStageCardsLoading(stage.id)"
                      class="i-lucide-loader-2 size-4 animate-spin"
                    />
                    <span v-else>{{
                      t('KANBAN.ACTIONS.LOAD_MORE_CARDS')
                    }}</span>
                  </button>
                </div>

                <div
                  v-if="canAddCardInStageFooter(stage)"
                  class="border-t border-n-weak p-2"
                >
                  <button
                    type="button"
                    data-testid="kanban-stage-add-card"
                    :data-stage-id="stage.id"
                    class="flex w-full items-center gap-2 rounded-md px-2 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                    :disabled="isActionActive(stageActionKey(stage))"
                    @click="toggleAddItemPicker(stage)"
                  >
                    <i class="i-lucide-plus size-4" />
                    {{ t('KANBAN.STAGE_MENU.ADD_CARD') }}
                  </button>
                </div>
              </section>
            </template>
          </Draggable>
          <button
            v-if="!isCreatingStageDraft"
            type="button"
            data-testid="kanban-create-stage-draft"
            class="flex w-80 flex-shrink-0 items-center justify-center gap-2 rounded-lg border border-dashed border-n-weak px-3 py-6 text-sm font-medium text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1 hover:text-n-brand"
            :aria-label="t('KANBAN.ACTIONS.CREATE_STAGE_DRAFT')"
            @click="openStageDraft"
          >
            <i class="i-lucide-plus size-4" />
            {{ t('KANBAN.ACTIONS.CREATE_STAGE_DRAFT') }}
          </button>
          <OnClickOutside
            v-else
            class="flex-shrink-0"
            @trigger="cancelStageDraft"
          >
            <section
              class="flex w-80 flex-shrink-0 flex-col gap-3 rounded-lg border border-dashed border-n-weak bg-n-alpha-1 p-3"
              @keydown.escape.prevent="cancelStageDraft"
            >
              <form class="flex flex-col gap-3" @submit.prevent="createStage">
                <div class="flex items-center gap-3">
                  <ColorPicker
                    v-model="newStageColor"
                    :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
                    data-testid="kanban-new-stage-color-picker"
                    class="flex-shrink-0"
                  />
                  <input
                    ref="newStageNameInput"
                    v-model="newStageName"
                    type="text"
                    data-testid="kanban-new-stage-name-input"
                    autofocus
                    class="reset-base !mb-0 h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                    :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
                  />
                </div>
                <div class="flex justify-end gap-2">
                  <NextButton
                    type="submit"
                    icon="i-lucide-check"
                    :label="t('KANBAN.ACTIONS.CREATE_STAGE_CONFIRM')"
                    color="blue"
                    size="sm"
                    :is-loading="isCreatingStage"
                    :disabled="isCreatingStage"
                    data-testid="kanban-create-stage-confirm"
                  />
                  <NextButton
                    icon="i-lucide-x"
                    :label="t('KANBAN.ACTIONS.CANCEL')"
                    color="slate"
                    variant="ghost"
                    size="sm"
                    :disabled="isCreatingStage"
                    data-testid="kanban-create-stage-cancel"
                    @click="cancelStageDraft"
                  />
                </div>
              </form>
            </section>
          </OnClickOutside>
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
