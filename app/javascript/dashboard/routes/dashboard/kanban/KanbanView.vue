<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
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
const activeActionKey = ref('');
const hasError = ref(false);
const selectedInboxIds = ref([]);
const selectedAssigneeIds = ref([]);
const isBoardDropdownOpen = ref(false);
const editingStageId = ref(null);
const stageNames = ref({});
const stageColors = ref({});
const stageNameInputs = new Map();
const activeAddItemStageId = ref(null);
const stageCardsLoading = ref({});
const stageCardsErrors = ref({});
const stageRefreshRequests = new Map();
const cardPendingRemoval = ref(null);
const stagePendingRemoval = ref(null);
const showRemoveCardConfirmation = ref(false);
const showRemoveStageConfirmation = ref(false);
const isCardDragging = ref(false);
const hasCardDragChanged = ref(false);
const suppressNextCardClick = ref(false);
const isPersistingCardDrag = ref(false);
const defaultStageColor = DEFAULT_KANBAN_STAGE_COLOR;
const newStageColor = ref(defaultStageColor);
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
const hasMultipleBoards = computed(() => boards.value.length > 1);
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
const isCardDragDisabled = computed(
  () => isPersistingCardDrag.value || !!activeActionKey.value
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
const currentFilterParams = () => ({
  ...currentInboxFilterParams(),
  ...currentAssigneeFilterParams(),
});
const currentBoardRequestConfig = () =>
  selectedInboxIds.value.length > 0 || selectedAssigneeIds.value.length > 0
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

const showActionError = (error, fallbackMessage) => {
  const message = isNameTakenError(error)
    ? t('KANBAN.ACTIONS.STAGE_NAME_TAKEN')
    : getErrorMessage(error, fallbackMessage);
  useAlert(message);
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
  }));
};

const applyStageFirstPage = (stageId, page) => {
  updateStageCards(stageId, stage => ({
    ...stage,
    cards: page.cards || [],
    pagination: page.pagination || stage.pagination,
    cardsCount: page.pagination?.totalCount ?? stage.cardsCount,
  }));
  setStageCardsError(stageId);
};

const fetchStageCardsPage = async (stageId, params) => {
  const response = await KanbanBoardsAPI.getStageCards(
    selectedBoard.value.id,
    stageId,
    {
      ...params,
      ...currentFilterParams(),
    }
  );

  return normalizeKanbanPayload(response.data);
};

const reloadStageCards = async stageId => {
  const page = await fetchStageCardsPage(stageId, {
    limit: stageCardsPageLimit,
  });
  applyStageFirstPage(stageId, page);
};

const refreshStageFirstPage = stageId => {
  if (!selectedBoard.value?.id || !stageId) return Promise.resolve();

  if (stageRefreshRequests.has(stageId)) {
    return stageRefreshRequests.get(stageId);
  }

  const request = reloadStageCards(stageId).finally(() => {
    stageRefreshRequests.delete(stageId);
  });

  stageRefreshRequests.set(stageId, request);
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

  setStageCardsLoading(stage.id, true);
  setStageCardsError(stage.id);

  try {
    const page = await fetchStageCardsPage(stage.id, {
      limit: stageCardsPageLimit,
      cursor: stage.pagination?.nextCursor,
    });
    applyStageCardsPage(stage.id, page);
  } catch (error) {
    if (isRefreshRequiredError(error)) {
      await reloadStageCards(stage.id);
      return;
    }

    setStageCardsError(stage.id, t('KANBAN.ACTIONS.LOAD_CARDS_ERROR'));
  } finally {
    setStageCardsLoading(stage.id, false);
  }
};

const getStageColorOption = getKanbanStageColorOption;

const getStageHeaderClass = stage =>
  getStageColorOption(stage.color).headerClass;

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

const showBoard = async boardId => {
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
    stageCardsLoading.value = {};
    stageCardsErrors.value = {};
    selectedBoard.value = normalizeKanbanPayload(response.data);
  } catch {
    hasError.value = true;
    selectedBoard.value = null;
  } finally {
    isFetchingBoard.value = false;
  }
};

const refreshSelectedBoard = async () => {
  if (!selectedBoard.value?.id) return;

  await showBoard(selectedBoard.value.id);
};

const updateInboxFilter = async inboxIds => {
  selectedInboxIds.value = [...new Set(inboxIds)];
  await refreshSelectedBoard();
};

const updateAssigneeFilter = async assigneeIds => {
  selectedAssigneeIds.value = [...new Set(assigneeIds)];
  await refreshSelectedBoard();
};

const openBoardSettings = () => {
  if (!selectedBoard.value?.id) return;

  router.push({
    name: 'kanban_board_settings',
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
    return;
  }

  activeAddItemStageId.value = stage.id;
};

const closeAddItemPicker = () => {
  activeAddItemStageId.value = null;
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

const onCardDragStart = () => {
  isCardDragging.value = true;
  hasCardDragChanged.value = false;
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

  const destinationPosition = targetIndex + 1;
  const stageChanged = card.kanbanStageId !== stage.id;
  const positionChanged = card.position !== destinationPosition;
  if (!stageChanged && !positionChanged) return;

  isPersistingCardDrag.value = true;
  activeActionKey.value = `reorder-card-${card.id}`;
  const payload = {
    card: {
      kanban_stage_id: stage.id,
      position: destinationPosition,
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
    showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
    await refreshStageFirstPages([card.kanbanStageId, stage.id]);
  } finally {
    isPersistingCardDrag.value = false;
    activeActionKey.value = '';
  }
};

const onCardDragEnd = () => {
  if (isCardDragging.value || hasCardDragChanged.value) {
    suppressNextCardClick.value = true;
    window.setTimeout(() => {
      suppressNextCardClick.value = false;
    }, 0);
  }

  isCardDragging.value = false;
  hasCardDragChanged.value = false;
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

const selectBoard = boardId => {
  if (boardId === activeBoardId.value) return;

  isBoardDropdownOpen.value = false;
  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
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
      await showBoard(nextBoardId);
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

const openConversation = (card, event = {}) => {
  if (!card?.conversationId) return;

  if (suppressNextCardClick.value) {
    suppressNextCardClick.value = false;
    return;
  }

  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: card.conversationId,
    })
  );

  if (event.metaKey || event.ctrlKey) {
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }

  router.push({ path });
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
};

const onOpportunityUpdated = updatedCard => {
  if (patchVisibleCard(updatedCard)) return;

  refreshStageFirstPage(
    findCardStageId({
      id: selectedOpportunityCardId.value,
      kanbanStageId: updatedCard?.kanbanStageId,
    })
  );
};

const onOpportunityOpenConversation = card => {
  openConversation(card, {});
  closeOpportunityDetails();
};

const handleRealtimeCardUpdated = async data => {
  if (Object.keys(currentFilterParams()).length > 0) {
    await refreshStageFirstPage(data.stage_id);
    return;
  }

  try {
    const response = await KanbanBoardsAPI.showCardById(
      selectedBoard.value.id,
      data.card_id
    );
    const card = normalizePayload(response.data);

    if (card.active === false || !patchVisibleCard(card)) {
      await refreshStageFirstPage(data.stage_id);
    }
  } catch {
    await refreshStageFirstPage(data.stage_id);
  }
};

const handleRealtimeKanbanEvent = ({ event, data } = {}) => {
  if (!selectedBoard.value?.id || data?.board_id !== selectedBoard.value.id) {
    return;
  }

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

watch(activeBoardId, (boardId, previousBoardId) => {
  if (!boards.value.length) return;

  if (previousBoardId && previousBoardId !== boardId) {
    selectedInboxIds.value = [];
    selectedAssigneeIds.value = [];
  }

  isBoardDropdownOpen.value = false;
  showBoard(boardId);
});

onMounted(() => {
  emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
  fetchBoards();
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <section class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex min-h-16 flex-wrap items-start justify-between gap-4 border-b border-n-weak px-6 py-3"
      >
        <div class="min-w-0 flex-1">
          <OnClickOutside @trigger="isBoardDropdownOpen = false">
            <div class="relative inline-flex max-w-full flex-col">
              <button
                type="button"
                data-testid="kanban-board-switcher"
                class="inline-flex max-w-full items-center gap-2 rounded-md px-1 py-1 text-left text-xl font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="!hasBoards"
                @click="
                  isBoardDropdownOpen =
                    hasMultipleBoards && !isBoardDropdownOpen
                "
              >
                <span class="truncate">{{ currentBoardName }}</span>
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
              </div>
            </div>
          </OnClickOutside>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <template v-if="selectedBoard">
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
            <div
              class="w-48 max-w-full flex-none"
              data-testid="kanban-inbox-filter"
            >
              <TagMultiSelectComboBox
                :model-value="selectedInboxIds"
                :options="inboxFilterOptions"
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
                :placeholder="t('KANBAN.FILTERS.AGENTS')"
                :search-placeholder="t('KANBAN.SETTINGS.AGENTS.SEARCH')"
                :empty-state="t('KANBAN.SETTINGS.AGENTS.EMPTY')"
                :disabled="!hasAgentFilterOptions"
                @update:model-value="updateAssigneeFilter"
              />
            </div>
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

      <div v-else class="flex min-h-0 flex-1 overflow-x-auto p-4">
        <Draggable
          v-model="stageListModel"
          item-key="id"
          class="flex min-h-0 gap-4"
          handle=".stage-drag-handle"
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
                class="stage-drag-handle cursor-grab flex min-h-14 items-center justify-between gap-2 px-3 py-2 text-white"
                :class="getStageHeaderClass(stage)"
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
                      class="min-w-0 flex-1 rounded-md border border-white/30 bg-white/90 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-white"
                      :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
                      @keydown.escape.prevent="cancelEditingStage"
                    />
                    <button
                      type="submit"
                      class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-50"
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
                      class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20"
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
                      class="size-5 rounded-full border border-white/40 ring-offset-2"
                      :class="[
                        colorOption.swatchClass,
                        stageColors[stage.id] === colorOption.value
                          ? 'ring-2 ring-white'
                          : 'hover:ring-2 hover:ring-white/70',
                      ]"
                      :aria-label="getSelectStageColorLabel(colorOption)"
                      @click="stageColors[stage.id] = colorOption.value"
                    />
                  </div>
                </form>
                <template v-else>
                  <div class="flex min-w-0 flex-1 items-center gap-2">
                    <h3 class="truncate text-sm font-medium">
                      {{ stage.name }}
                    </h3>
                    <span
                      class="flex-shrink-0 rounded-full bg-white/20 px-2 py-0.5 text-xs font-medium"
                    >
                      {{ stage.cards.length }}
                    </span>
                  </div>
                  <div class="flex flex-shrink-0 gap-1">
                    <button
                      type="button"
                      class="flex size-8 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="!!activeActionKey"
                      :aria-label="t('KANBAN.ACTIONS.EDIT_STAGE')"
                      @click="startEditingStage(stage)"
                    >
                      <i class="i-lucide-pencil size-4" />
                    </button>
                    <button
                      type="button"
                      class="flex size-8 items-center justify-center rounded-md border border-white/30 bg-white/10 text-white hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="!!activeActionKey"
                      :aria-label="t('KANBAN.ACTIONS.REMOVE_STAGE')"
                      @click="openRemoveStageConfirmation(stage)"
                    >
                      <i class="i-lucide-x size-4" />
                    </button>
                  </div>
                </template>
              </header>

              <div
                class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto bg-n-solid-1 p-3"
              >
                <button
                  type="button"
                  data-testid="kanban-add-item-button"
                  :data-stage-id="stage.id"
                  class="no-drag flex w-full items-center justify-center gap-1 rounded-md border border-dashed border-n-weak bg-n-alpha-1 px-3 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="!!activeActionKey"
                  :aria-expanded="activeAddItemStageId === stage.id"
                  :aria-controls="`kanban-add-item-panel-${stage.id}`"
                  :title="t('KANBAN.ACTIONS.ADD_ITEM')"
                  @click="toggleAddItemPicker(stage)"
                >
                  <i class="i-lucide-plus size-4" />
                  {{ t('KANBAN.ACTIONS.ADD_ITEM') }}
                </button>

                <KanbanOpportunityPicker
                  v-if="activeAddItemStageId === stage.id"
                  :kanban-board-id="selectedBoard.id"
                  :kanban-stage-id="stage.id"
                  @created="refreshStageFirstPage(stage.id)"
                  @close="closeAddItemPicker"
                />

                <Draggable
                  :list="stage.cards"
                  item-key="id"
                  class="flex min-h-48 flex-1 flex-col gap-2 rounded-md"
                  :group="{ name: 'kanban-cards' }"
                  handle=".card-drag-handle"
                  :filter="cardDragFilter"
                  :prevent-on-filter="false"
                  :empty-insert-threshold="80"
                  :swap-threshold="0.65"
                  fallback-on-body
                  force-fallback
                  :disabled="isCardDragDisabled"
                  ghost-class="opacity-60"
                  chosen-class="opacity-90"
                  :animation="180"
                  @start="onCardDragStart"
                  @change="onCardDragChange(stage, $event)"
                  @end="onCardDragEnd"
                >
                  <p
                    v-if="stage.cards.length === 0"
                    class="pointer-events-none px-1 py-2 text-sm text-n-slate-10"
                  >
                    {{ t('KANBAN.EMPTY_CARDS') }}
                  </p>
                  <template #item="{ element: card }">
                    <KanbanConversationCard
                      :card="card"
                      :active-action-key="activeActionKey"
                      @open-details="openDetails"
                      @open-conversation="openConversation"
                      @remove-card="openRemoveCardConfirmation"
                    />
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
                  class="no-drag flex w-full items-center justify-center gap-1 rounded-md border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isStageCardsLoading(stage.id)"
                  @click="loadMoreStageCards(stage)"
                >
                  <i class="i-lucide-loader-2 size-4" />
                  {{
                    isStageCardsLoading(stage.id)
                      ? t('KANBAN.ACTIONS.LOADING_CARDS')
                      : t('KANBAN.ACTIONS.LOAD_MORE_CARDS')
                  }}
                </button>
              </div>
            </section>
          </template>
        </Draggable>
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
      size="modal-big"
      :on-close="closeOpportunityDetails"
    >
      <KanbanOpportunityDetailsModal
        :board-id="selectedBoard.id"
        :board-name="selectedBoard.name"
        :card-id="selectedOpportunityCardId"
        @close="closeOpportunityDetails"
        @updated="onOpportunityUpdated"
        @open-conversation="onOpportunityOpenConversation"
      />
    </woot-modal>
  </main>
</template>
