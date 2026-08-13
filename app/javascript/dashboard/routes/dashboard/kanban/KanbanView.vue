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
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { frontendURL, kanbanConversationUrl } from 'dashboard/helper/URLHelper';
import { pushEmbedded } from 'dashboard/helper/embeddedConversationHistory';
import {
  getKanbanBoardSnapshot,
  removeKanbanBoardSnapshot,
  saveKanbanBoardSnapshot,
} from 'dashboard/helper/kanbanBoardSnapshot';
import {
  DEFAULT_KANBAN_STAGE_COLOR,
  KANBAN_STAGE_COLOR_OPTIONS,
  getKanbanStageColorOption,
} from 'dashboard/helper/kanbanStageColors';
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
const selectedOpportunityCardId = ref(null);
const opportunityModalRef = ref(null);
const showUnsavedOpportunityChangesConfirm = ref(false);
const isSavingOpportunityBeforeExit = ref(false);
const activeActionKey = ref('');
const hasError = ref(false);
const selectedInboxIds = ref([]);
const selectedAssigneeIds = ref([]);
const isBoardDropdownOpen = ref(false);
const openStageMenuId = ref(null);
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
const showRemoveCardConfirmation = ref(false);
const showRemoveStageConfirmation = ref(false);
const isCardDragging = ref(false);
const pendingRealtimeKanbanEvents = ref([]);
const hasCardDragChanged = ref(false);
const suppressNextCardClick = ref(false);
const isPersistingCardDrag = ref(false);
const defaultStageColor = DEFAULT_KANBAN_STAGE_COLOR;
const newStageColor = ref(defaultStageColor);
const boardScrollContainer = ref(null);
const pendingScrollToStageId = ref(null);
const searchInput = ref('');
const activeSearchTerm = ref('');
let searchDebounceTimer = null;
let searchRequestToken = 0;
const preSearchScrollLeft = ref(null);
let requestGeneration = 0;
const staleRequest = Symbol('stale-kanban-request');

let dragMouseX = -1;
let dragPointerReady = false;
let autoScrollRaf = null;
const onDragMouseMove = e => {
  dragMouseX = e.clientX;
  dragPointerReady = true;
};
const runBoardAutoScroll = () => {
  const el = boardScrollContainer.value;
  if (el && dragPointerReady) {
    const { left, right } = el.getBoundingClientRect();
    const threshold = 100;
    const speed = 18;
    if (dragMouseX < left + threshold) {
      el.scrollLeft -= speed;
    } else if (dragMouseX > right - threshold) {
      el.scrollLeft += speed;
    }
  }
  autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
};
const startBoardAutoScroll = () => {
  dragPointerReady = false;
  dragMouseX = -1;
  document.addEventListener('mousemove', onDragMouseMove);
  autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
};
const stopBoardAutoScroll = () => {
  document.removeEventListener('mousemove', onDragMouseMove);
  if (autoScrollRaf) cancelAnimationFrame(autoScrollRaf);
  autoScrollRaf = null;
  dragPointerReady = false;
};
const cardDragFilter =
  'button,a,input,textarea,select,[contenteditable="true"],.no-drag';
const stageCardsPageLimit = 20;
const boardRefreshEvents = new Set([
  'kanban.board.updated',
  'kanban.stage.created',
  'kanban.stage.updated',
  'kanban.stage.deleted',
  'kanban.stage.reordered',
]);

const stageColorOptions = KANBAN_STAGE_COLOR_OPTIONS;

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const stages = computed(() => selectedBoard.value?.stages || []);
const hasBoards = computed(() => boards.value.length > 0);
const activeAddItemStage = computed(() =>
  stages.value.find(stage => stage.id === activeAddItemStageId.value)
);
const isInitialLoading = computed(
  () => isFetchingBoards.value && !selectedBoard.value
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
const hasInboxFilterOptions = computed(
  () => inboxFilterOptions.value.length > 0
);
const agentFilterOptions = computed(() =>
  agents.value.map(agent => ({
    value: agent.id,
    label: agent.name || agent.email,
  }))
);
const hasAgentFilterOptions = computed(
  () => agentFilterOptions.value.length > 0
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
const hasActiveFilters = computed(
  () =>
    selectedInboxIds.value.length > 0 ||
    selectedAssigneeIds.value.length > 0 ||
    activeSearchTerm.value.length >= 2
);
const isSearchLoading = computed(
  () => isFetchingBoard.value && searchInput.value !== ''
);
const isCardDragDisabled = computed(
  () =>
    isPersistingCardDrag.value ||
    !!activeActionKey.value ||
    hasActiveFilters.value
);
const canAddCardInEmptyStage = stage =>
  !isTerminalStage(stage) && !hasActiveFilters.value && !isCardDragging.value;
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

const currentInboxFilterParams = () =>
  selectedInboxIds.value.length > 0
    ? { inbox_ids: selectedInboxIds.value }
    : {};
const currentAssigneeFilterParams = () =>
  selectedAssigneeIds.value.length > 0
    ? { assignee_ids: selectedAssigneeIds.value }
    : {};
const currentSearchParams = () =>
  activeSearchTerm.value.length >= 2 ? { q: activeSearchTerm.value } : {};
const currentFilterParams = () => ({
  ...currentInboxFilterParams(),
  ...currentAssigneeFilterParams(),
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

const showActionError = (error, fallbackMessage) => {
  let message = getErrorMessage(error, fallbackMessage);
  if (isNameTakenError(error)) message = t('KANBAN.ACTIONS.STAGE_NAME_TAKEN');
  if (isSpecialStageOrderError(error))
    message = t('KANBAN.ACTIONS.STAGE_ORDER_INVALID');

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

const getStageColorOption = getKanbanStageColorOption;

const getStageColorLabel = colorOption => {
  const labels = {
    slate: t('KANBAN.COLORS.SLATE'),
    blue: t('KANBAN.COLORS.BLUE'),
    teal: t('KANBAN.COLORS.TEAL'),
    green: t('KANBAN.COLORS.GREEN'),
    amber: t('KANBAN.COLORS.AMBER'),
    orange: t('KANBAN.COLORS.ORANGE'),
    ruby: t('KANBAN.COLORS.RUBY'),
    rose: t('KANBAN.COLORS.ROSE'),
    violet: t('KANBAN.COLORS.VIOLET'),
    iris: t('KANBAN.COLORS.IRIS'),
  };

  return labels[colorOption.value];
};

const getSelectStageColorLabel = colorOption =>
  t('KANBAN.ACTIONS.SELECT_STAGE_COLOR', {
    color: getStageColorLabel(colorOption),
  });

const getEffectiveStageColor = stage =>
  editingStageId.value === stage.id
    ? stageColors.value[stage.id] || stage.color
    : stage.color;

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
        inboxIds: selectedInboxIds.value,
        assigneeIds: selectedAssigneeIds.value,
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

  selectedInboxIds.value = snapshot.filters?.inboxIds || [];
  selectedAssigneeIds.value = snapshot.filters?.assigneeIds || [];
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

const updateInboxFilter = async inboxIds => {
  selectedInboxIds.value = [...new Set(inboxIds)];
  requestGeneration += 1;
  await refreshSelectedBoard();
};

const updateAssigneeFilter = async assigneeIds => {
  selectedAssigneeIds.value = [...new Set(assigneeIds)];
  requestGeneration += 1;
  await refreshSelectedBoard();
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

const findCreatedStage = (createdStage, temporaryName) => {
  if (createdStage?.id) {
    return stages.value.find(stage => stage.id === createdStage.id);
  }

  return stages.value.find(stage => stage.name === temporaryName);
};

const getUniqueTemporaryStageName = () => {
  const baseName = t('KANBAN.ACTIONS.NEW_STAGE_NAME');
  const existingNames = new Set(stages.value.map(stage => stage.name));

  if (!existingNames.has(baseName)) return baseName;

  let suffix = 1;
  let nextName = `${baseName} (${suffix})`;

  while (existingNames.has(nextName)) {
    suffix += 1;
    nextName = `${baseName} (${suffix})`;
  }

  return nextName;
};

const startEditingStage = stage => {
  editingStageId.value = stage.id;
  stageNames.value = {
    ...stageNames.value,
    [stage.id]: stage.name,
  };
  stageColors.value = {
    ...stageColors.value,
    [stage.id]: getStageColorOption(stage.color).value,
  };
  nextTick(() => stageNameInputs.get(stage.id)?.focus());
};

const createStage = async () => {
  if (!selectedBoard.value?.id || isCreatingStage.value) return;

  const name = getUniqueTemporaryStageName();

  isCreatingStage.value = true;

  try {
    const response = await KanbanBoardsAPI.createStage(selectedBoard.value.id, {
      stage: {
        name,
        color: newStageColor.value,
        position: stages.value.length,
      },
    });
    newStageColor.value = defaultStageColor;
    const createdStage = normalizePayload(response.data);
    pendingScrollToStageId.value = createdStage.id;
    await refreshSelectedBoard();
    const stageToEdit = findCreatedStage(createdStage, name);
    if (stageToEdit) startEditingStage(stageToEdit);
    useAlert(t('KANBAN.ACTIONS.CREATE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
  } finally {
    isCreatingStage.value = false;
  }
};

const cancelEditingStage = () => {
  editingStageId.value = null;
};

const updateStage = async stage => {
  const name = String(stageNames.value[stage.id] || '').trim();
  const color = stageColors.value[stage.id] || defaultStageColor;
  if (!selectedBoard.value?.id || !name || activeActionKey.value) return;

  activeActionKey.value = `update-stage-${stage.id}`;

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
    activeActionKey.value = '';
  }
};

const openRemoveStageConfirmation = stage => {
  if (stage.cards.length > 0) {
    showActionError(null, t('KANBAN.ACTIONS.REMOVE_STAGE_NOT_EMPTY'));
    return;
  }

  stagePendingRemoval.value = stage;
  showRemoveStageConfirmation.value = true;
};

const closeRemoveStageConfirmation = () => {
  showRemoveStageConfirmation.value = false;
  stagePendingRemoval.value = null;
};

const removeStage = async stage => {
  if (!selectedBoard.value?.id || !stage?.id || activeActionKey.value) return;

  activeActionKey.value = `remove-stage-${stage.id}`;

  try {
    await KanbanBoardsAPI.deleteStage(selectedBoard.value.id, stage.id);
    await refreshSelectedBoard();
    useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR'));
  } finally {
    activeActionKey.value = '';
  }
};

const confirmRemoveStage = async () => {
  const stage = stagePendingRemoval.value;
  closeRemoveStageConfirmation();

  if (!stage) return;

  await removeStage(stage);
};

const toggleAddItemPicker = stage => {
  if (activeAddItemStageId.value === stage.id) {
    activeAddItemStageId.value = null;
    showDiscardAddItemConfirm.value = false;
    return;
  }

  activeAddItemStageId.value = stage.id;
};

function closeAddItemPicker() {
  activeAddItemStageId.value = null;
  showDiscardAddItemConfirm.value = false;
}

const attemptCloseAddItemPicker = () => {
  if (addItemPickerRef.value?.hasUnsavedSubject?.()) {
    showDiscardAddItemConfirm.value = true;
    return;
  }

  closeAddItemPicker();
};

const keepEditingAddItem = () => {
  showDiscardAddItemConfirm.value = false;
};

const discardAddItem = () => {
  closeAddItemPicker();
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
  if (!selectedBoard.value?.id || !stage?.id || activeActionKey.value) return;

  activeActionKey.value = `reorder-stage-${stage.id}`;

  try {
    await KanbanBoardsAPI.reorderStage(selectedBoard.value.id, stage.id, {
      position,
    });
    await refreshSelectedBoard();
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
    await refreshSelectedBoard();
  } finally {
    activeActionKey.value = '';
  }
};

const onStageDragEnd = async event => {
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
  const positionChanged =
    appendsToStageEnd || card.position !== destinationPosition;
  if (!stageChanged && !positionChanged) return;

  isPersistingCardDrag.value = true;
  activeActionKey.value = `reorder-card-${card.id}`;
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
    activeActionKey.value = '';
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
  if (!selectedBoard.value?.id || activeActionKey.value) return;

  activeActionKey.value = `remove-card-${card.id}`;

  try {
    await KanbanBoardsAPI.deleteCardById(selectedBoard.value.id, card.id);
    await refreshStageFirstPage(findCardStageId(card));
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
  } catch (error) {
    showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  } finally {
    activeActionKey.value = '';
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
  if (!selectedBoard.value?.id || activeActionKey.value) return;

  activeActionKey.value = `change-status-${card.id}`;

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
    activeActionKey.value = '';
  }
};

const closeBoardDropdown = () => {
  isBoardDropdownOpen.value = false;
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
const removeStageMessageValue = computed(
  () => stagePendingRemoval.value?.name || ''
);

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
    selectedInboxIds.value = [];
    selectedAssigneeIds.value = [];
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
        class="flex min-h-16 flex-wrap items-center justify-between gap-4 border-b border-n-weak px-6 py-3"
      >
        <div class="flex min-w-0 flex-1 items-center gap-1">
          <NextButton
            data-testid="kanban-back-to-overview"
            icon="i-lucide-chevron-left"
            variant="ghost"
            color="slate"
            size="sm"
            class="flex-shrink-0"
            :aria-label="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
            :title="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
            @click="goToOverview"
          />
          <OnClickOutside @trigger="closeBoardDropdown">
            <div class="relative inline-flex min-w-0 max-w-full flex-col">
              <button
                type="button"
                data-testid="kanban-board-switcher"
                class="inline-flex min-w-0 max-w-full items-center gap-2 rounded-md px-1 py-1 text-left text-xl font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="!hasBoards"
                @click="isBoardDropdownOpen = hasBoards && !isBoardDropdownOpen"
              >
                <span class="min-w-0 truncate">{{ currentBoardName }}</span>
                <i class="i-lucide-chevron-down size-5 text-n-slate-11" />
              </button>
              <div
                v-if="isBoardDropdownOpen"
                data-testid="kanban-board-switcher-dropdown"
                class="absolute left-0 top-full z-10 mt-2 w-96 max-w-[calc(100vw-2rem)] overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-sm"
              >
                <button
                  v-for="board in boards"
                  :key="board.id"
                  type="button"
                  class="flex w-full items-center justify-between gap-3 px-4 py-3 text-left text-sm text-n-slate-12 hover:bg-n-alpha-1"
                  @click="selectBoard(board.id)"
                >
                  <span
                    class="overflow-hidden text-ellipsis whitespace-nowrap"
                    :title="board.name"
                  >
                    {{ board.name }}
                  </span>
                  <i
                    v-if="board.id === activeBoardId"
                    class="i-lucide-check size-4 flex-shrink-0 text-n-brand"
                  />
                </button>
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
            class="w-64 max-w-full flex-none ltr:ml-2 rtl:mr-2"
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
              class="w-48 max-w-full flex-none"
              data-testid="kanban-inbox-filter"
            >
              <TagMultiSelectComboBox
                :model-value="selectedInboxIds"
                :options="inboxFilterOptions"
                icon="i-lucide-inbox"
                summary-mode
                :all-label="t('KANBAN.SETTINGS.INBOXES.ALL')"
                :selected-label="t('KANBAN.SETTINGS.INBOXES.SELECTED')"
                :placeholder="t('KANBAN.SETTINGS.INBOXES.PLACEHOLDER')"
                :search-placeholder="t('KANBAN.SETTINGS.INBOXES.SEARCH')"
                :empty-state="t('KANBAN.SETTINGS.INBOXES.EMPTY')"
                :disabled="!hasInboxFilterOptions"
                @update:model-value="updateInboxFilter"
              />
            </div>
            <div
              class="w-48 max-w-full flex-none"
              data-testid="kanban-agent-filter"
            >
              <TagMultiSelectComboBox
                :model-value="selectedAssigneeIds"
                :options="agentFilterOptions"
                icon="i-lucide-users"
                summary-mode
                :all-label="t('KANBAN.SETTINGS.AGENTS.ALL')"
                :selected-label="t('KANBAN.SETTINGS.AGENTS.SELECTED')"
                :placeholder="t('KANBAN.FILTERS.AGENTS')"
                :search-placeholder="t('KANBAN.SETTINGS.AGENTS.SEARCH')"
                :empty-state="t('KANBAN.SETTINGS.AGENTS.EMPTY')"
                :disabled="!hasAgentFilterOptions"
                @update:model-value="updateAssigneeFilter"
              />
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
              class="flex items-center gap-1 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="isCreatingStage"
              @click="createStage"
            >
              <i class="i-lucide-plus size-4" />
              {{ t('KANBAN.ACTIONS.CREATE_STAGE') }}
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
        v-else-if="isInitialLoading || isFetchingBoard"
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
        v-else-if="hasBoards && stages.length === 0"
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
        v-else-if="hasBoards && stages.length > 0"
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
        >
          <Draggable
            v-model="stageListModel"
            item-key="id"
            class="flex min-h-0 gap-4"
            handle=".stage-drag-handle"
            :move="canMoveStage"
            ghost-class="opacity-60"
            chosen-class="opacity-90"
            :animation="180"
            @end="onStageDragEnd"
          >
            <template #item="{ element: stage }">
              <section
                :data-stage-id="stage.id"
                class="flex w-80 flex-shrink-0 flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1"
              >
                <header
                  class="stage-drag-handle cursor-grab flex min-h-10 items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
                >
                  <form
                    v-if="editingStageId === stage.id"
                    class="grid min-w-0 flex-1 gap-2"
                    @submit.prevent="updateStage(stage)"
                  >
                    <div class="flex min-w-0 gap-2">
                      <input
                        :ref="element => setStageNameInput(stage.id, element)"
                        v-model="stageNames[stage.id]"
                        type="text"
                        class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                        :placeholder="
                          t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')
                        "
                        @keydown.escape.prevent="cancelEditingStage"
                      />
                      <button
                        type="submit"
                        class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                        :disabled="
                          !String(stageNames[stage.id] || '').trim() ||
                          !!activeActionKey
                        "
                        :aria-label="t('KANBAN.ACTIONS.SAVE_STAGE')"
                        :title="t('KANBAN.ACTIONS.SAVE_STAGE')"
                      >
                        <i class="i-lucide-check size-4" />
                      </button>
                      <button
                        type="button"
                        class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
                        :aria-label="t('KANBAN.ACTIONS.CANCEL')"
                        :title="t('KANBAN.ACTIONS.CANCEL')"
                        @click="cancelEditingStage"
                      >
                        <i class="i-lucide-x size-4" />
                      </button>
                    </div>
                    <div
                      class="flex items-center gap-1.5"
                      :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
                    >
                      <button
                        v-for="colorOption in stageColorOptions"
                        :key="colorOption.value"
                        type="button"
                        class="size-5 rounded-full border border-n-weak ring-offset-2"
                        :class="[
                          colorOption.swatchClass,
                          stageColors[stage.id] === colorOption.value
                            ? 'ring-2 ring-n-brand'
                            : 'hover:ring-2 hover:ring-n-slate-6',
                        ]"
                        :aria-label="getSelectStageColorLabel(colorOption)"
                        @click="stageColors[stage.id] = colorOption.value"
                      />
                    </div>
                  </form>
                  <template v-else>
                    <div class="flex min-w-0 flex-1 items-center gap-2">
                      <span
                        class="size-2.5 flex-shrink-0 rounded-full"
                        :class="
                          getStageColorOption(getEffectiveStageColor(stage))
                            .headerClass
                        "
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
                      <button
                        v-if="!isTerminalStage(stage)"
                        type="button"
                        data-testid="kanban-add-item-button"
                        class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                        :disabled="!!activeActionKey"
                        :aria-label="t('KANBAN.ACTIONS.ADD_ITEM')"
                        :title="t('KANBAN.ACTIONS.ADD_ITEM')"
                        @click="toggleAddItemPicker(stage)"
                      >
                        <i class="i-lucide-plus size-4" />
                      </button>
                      <OnClickOutside
                        class="relative"
                        @trigger="
                          openStageMenuId === stage.id &&
                            (openStageMenuId = null)
                        "
                      >
                        <button
                          type="button"
                          class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                          :disabled="!!activeActionKey"
                          :aria-label="t('KANBAN.ACTIONS.STAGE_OPTIONS')"
                          @click="
                            openStageMenuId =
                              openStageMenuId === stage.id ? null : stage.id
                          "
                        >
                          <i class="i-lucide-more-horizontal size-4" />
                        </button>
                        <div
                          v-if="openStageMenuId === stage.id"
                          class="absolute right-0 top-full z-20 mt-1 min-w-36 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-sm"
                        >
                          <button
                            type="button"
                            class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-1"
                            @click="
                              startEditingStage(stage);
                              openStageMenuId = null;
                            "
                          >
                            <i class="i-lucide-pencil size-4 text-n-slate-10" />
                            {{ t('KANBAN.ACTIONS.EDIT_STAGE') }}
                          </button>
                          <button
                            type="button"
                            class="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-ruby-11 hover:bg-n-ruby-2"
                            @click="
                              openRemoveStageConfirmation(stage);
                              openStageMenuId = null;
                            "
                          >
                            <i class="i-lucide-trash size-4" />
                            {{ t('KANBAN.ACTIONS.REMOVE_STAGE') }}
                          </button>
                        </div>
                      </OnClickOutside>
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
                    class="flex min-h-48 flex-shrink-0 flex-col gap-2 rounded-md"
                    :title="
                      hasActiveFilters
                        ? t('KANBAN.ACTIONS.REORDER_DISABLED_FILTERED')
                        : undefined
                    "
                    :group="{ name: 'kanban-cards' }"
                    handle=".card-drag-handle"
                    :filter="cardDragFilter"
                    :prevent-on-filter="false"
                    :empty-insert-threshold="5"
                    :swap-threshold="0.65"
                    :inverted-swap-threshold="1"
                    fallback-on-body
                    force-fallback
                    :disabled="isCardDragDisabled"
                    ghost-class="opacity-60"
                    chosen-class="opacity-90"
                    :animation="isCardDragging ? 0 : 180"
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
                        :active-action-key="activeActionKey"
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
                          :disabled="!!activeActionKey"
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
              </section>
            </template>
          </Draggable>
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
      :title="t('KANBAN.REMOVE_STAGE.TITLE')"
      :message="t('KANBAN.REMOVE_STAGE.MESSAGE')"
      :message-value="removeStageMessageValue"
      :confirm-text="t('KANBAN.REMOVE_STAGE.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_STAGE.CANCEL')"
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

    <woot-modal
      :show="showDiscardAddItemConfirm"
      :show-close-button="false"
      size="modal-narrow"
      :on-close="keepEditingAddItem"
    >
      <div class="p-6">
        <p class="mb-6 text-sm text-n-slate-11">
          {{ t('KANBAN.ADD_ITEM.DISCARD_CONFIRM') }}
        </p>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <NextButton
            outline
            slate
            sm
            :label="t('KANBAN.OPPORTUNITY_DETAILS.KEEP_EDITING')"
            @click="keepEditingAddItem"
          />
          <NextButton
            ruby
            sm
            :label="t('KANBAN.BOARD_EDIT.DISCARD')"
            @click="discardAddItem"
          />
        </div>
      </div>
    </woot-modal>
  </main>
</template>
