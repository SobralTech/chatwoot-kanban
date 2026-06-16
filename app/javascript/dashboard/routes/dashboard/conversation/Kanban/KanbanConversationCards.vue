<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { getKanbanStageColorClass } from 'dashboard/helper/kanbanStageColors';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import KanbanDueDatePicker from '../../kanban/KanbanDueDatePicker.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const accountLabels = useMapGetter('labels/getLabels');

const cards = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const requestId = ref(0);
const abortController = ref(null);
const boardsAbortController = ref(null);
const stagesAbortController = ref(null);
const createAbortController = ref(null);
const boardsRequestId = ref(0);
const stagesRequestId = ref(0);
const editStagesRequestId = ref(0);

const isFormOpen = ref(false);
const boards = ref([]);
const stages = ref([]);
const selectedBoardId = ref('');
const selectedStageId = ref('');
const subject = ref('');
const dueAt = ref('');
const selectedLabelTitles = ref([]);
const isLoadingBoards = ref(false);
const isLoadingStages = ref(false);
const isCreating = ref(false);
const boardsError = ref('');
const stagesError = ref('');
const createError = ref('');
const editingCardId = ref(null);
const editStages = ref([]);
const editSubject = ref('');
const editStageId = ref('');
const editDueAt = ref('');
const editLabelTitles = ref([]);
const editError = ref('');
const isLoadingEditStages = ref(false);
const isSavingEdit = ref(false);
const hasPendingEditSave = ref(false);
const editStagesAbortController = ref(null);
const hasPendingRealtimeRefresh = ref(false);
const deleteDialogRef = ref(null);
const cardToDelete = ref(null);
const isDeletingCard = ref(false);
const editSaveTimer = ref(null);
const editingCard = ref(null);

const EDIT_AUTOSAVE_DELAY = 800;

const cancelScheduledEdit = () => {
  if (!editSaveTimer.value) return;

  clearTimeout(editSaveTimer.value);
  editSaveTimer.value = null;
};

const kanbanCardRealtimeEvents = new Set([
  'kanban.card.created',
  'kanban.card.updated',
  'kanban.card.deleted',
  'kanban.card.reordered',
]);

const hasCards = computed(() => cards.value.length > 0);
const activeBoards = computed(() =>
  boards.value.filter(board => board.active !== false)
);
const activeStages = computed(() =>
  stages.value.filter(stage => stage.active !== false)
);
const activeEditStages = computed(() =>
  editStages.value.filter(stage => stage.active !== false)
);
const selectedBoard = computed(() =>
  activeBoards.value.find(
    board => Number(board.id) === Number(selectedBoardId.value)
  )
);
const selectedStage = computed(() =>
  activeStages.value.find(
    stage => Number(stage.id) === Number(selectedStageId.value)
  )
);
const selectedEditStage = computed(() =>
  activeEditStages.value.find(
    stage => Number(stage.id) === Number(editStageId.value)
  )
);
const selectedLabels = computed(() =>
  accountLabels.value.filter(label =>
    selectedLabelTitles.value.includes(label.title)
  )
);
const selectedLabelsSummary = computed(() =>
  selectedLabelTitles.value.length
    ? selectedLabelTitles.value.join(', ')
    : t('CONVERSATION_SIDEBAR.KANBAN.NO_LABELS_SELECTED')
);
const editLabelsSummary = computed(() =>
  editLabelTitles.value.length
    ? editLabelTitles.value.join(', ')
    : t('CONVERSATION_SIDEBAR.KANBAN.NO_LABELS_SELECTED')
);
const canSubmit = computed(
  () => selectedBoardId.value && selectedStageId.value && !isCreating.value
);
const canSaveEdit = computed(
  () => editSubject.value.trim() && editStageId.value && !isSavingEdit.value
);
const hasOpenLocalForm = computed(
  () => isFormOpen.value || editingCardId.value !== null
);

const contactId = computed(() => currentChat.value?.meta?.sender?.id);
const inboxId = computed(
  () => currentChat.value?.inbox_id || currentChat.value?.inboxId
);
const inbox = computed(() => {
  const getInboxById = store.getters?.['inboxes/getInboxById'];
  return getInboxById?.(inboxId.value) || {};
});
const defaultSubject = computed(() => {
  const contactName =
    currentChat.value?.meta?.sender?.name?.trim() ||
    `Contact #${contactId.value}`;
  const inboxName = inbox.value?.name?.trim() || `Inbox #${inboxId.value}`;

  return `${contactName} - ${inboxName}`;
});

const stageColorClass = getKanbanStageColorClass;

const formatDueAt = value => {
  if (!value) return t('CONVERSATION_SIDEBAR.KANBAN.NOT_SET');

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return t('CONVERSATION_SIDEBAR.KANBAN.NOT_SET');
  }

  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');

  return `${day}/${month}/${date.getFullYear()}`;
};

const formatDateInput = value => {
  if (!value) return '';

  const dateOnlyMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (dateOnlyMatch) return value;

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
};

const normalizeCollection = response =>
  response.data?.payload || response.data || [];

const isAbortError = error =>
  error?.name === 'AbortError' || error?.name === 'CanceledError';

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallback;

const resetAbortController = () => {
  abortController.value?.abort();
  abortController.value = null;
};

const abortFormRequests = () => {
  boardsAbortController.value?.abort();
  stagesAbortController.value?.abort();
  createAbortController.value?.abort();
  boardsAbortController.value = null;
  stagesAbortController.value = null;
  createAbortController.value = null;
  boardsRequestId.value += 1;
  stagesRequestId.value += 1;
};

const abortEditRequests = () => {
  editStagesAbortController.value?.abort();
  editStagesAbortController.value = null;
  editStagesRequestId.value += 1;
};

const resetFormState = () => {
  abortFormRequests();
  isFormOpen.value = false;
  boards.value = [];
  stages.value = [];
  selectedBoardId.value = '';
  selectedStageId.value = '';
  subject.value = '';
  dueAt.value = '';
  selectedLabelTitles.value = [];
  isLoadingBoards.value = false;
  isLoadingStages.value = false;
  isCreating.value = false;
  boardsError.value = '';
  stagesError.value = '';
  createError.value = '';
};

const resetEditState = () => {
  cancelScheduledEdit();
  abortEditRequests();
  editingCardId.value = null;
  editingCard.value = null;
  editStages.value = [];
  editSubject.value = '';
  editStageId.value = '';
  editDueAt.value = '';
  editLabelTitles.value = [];
  editError.value = '';
  isLoadingEditStages.value = false;
  isSavingEdit.value = false;
  hasPendingEditSave.value = false;
};

const conversationIdFromRealtimeData = data =>
  data?.conversation_id ?? data?.conversationId ?? data?.card?.conversation_id;

const isCurrentConversationRealtimeData = data => {
  const eventConversationId = conversationIdFromRealtimeData(data);
  if (!eventConversationId) return true;

  return String(eventConversationId) === String(props.conversationId);
};

const shouldRefreshForRealtimeEvent = ({ event, data } = {}) => {
  if (!kanbanCardRealtimeEvents.has(event)) return false;

  return isCurrentConversationRealtimeData(data);
};

const loadCards = async () => {
  if (!props.conversationId) return;

  const currentRequestId = requestId.value + 1;
  requestId.value = currentRequestId;
  resetAbortController();

  const controller = new AbortController();
  abortController.value = controller;
  isLoading.value = true;
  hasError.value = false;

  try {
    const response = await KanbanBoardsAPI.getConversationCards(
      props.conversationId,
      { signal: controller.signal }
    );

    if (requestId.value !== currentRequestId || controller.signal.aborted) {
      return;
    }

    cards.value = response.data?.payload || [];
  } catch (error) {
    if (isAbortError(error) || requestId.value !== currentRequestId) {
      return;
    }

    cards.value = [];
    hasError.value = true;
  } finally {
    if (requestId.value === currentRequestId) {
      isLoading.value = false;
      abortController.value = null;

      if (hasPendingRealtimeRefresh.value && !hasOpenLocalForm.value) {
        hasPendingRealtimeRefresh.value = false;
        loadCards();
      }
    }
  }
};

const refreshCardsFromRealtime = () => {
  if (hasOpenLocalForm.value || isLoading.value) {
    hasPendingRealtimeRefresh.value = true;
    return;
  }

  loadCards();
};

const flushPendingRealtimeRefresh = () => {
  if (!hasPendingRealtimeRefresh.value || hasOpenLocalForm.value) return;

  hasPendingRealtimeRefresh.value = false;
  loadCards();
};

const cardBoardId = card => card.kanban_board_id || card.kanban_board?.id;

const cardStageId = card => card.kanban_stage_id || card.kanban_stage?.id;

const loadStages = async boardId => {
  if (!boardId) return;

  const currentRequestId = stagesRequestId.value + 1;
  stagesRequestId.value = currentRequestId;
  stagesAbortController.value?.abort();

  const controller = new AbortController();
  stagesAbortController.value = controller;
  isLoadingStages.value = true;
  stagesError.value = '';
  stages.value = [];
  selectedStageId.value = '';

  try {
    const response = await KanbanBoardsAPI.showBoard(boardId, {
      signal: controller.signal,
    });

    if (
      stagesRequestId.value !== currentRequestId ||
      controller.signal.aborted
    ) {
      return;
    }

    stages.value = response.data?.stages || [];
    selectedStageId.value = activeStages.value[0]?.id || '';
  } catch (error) {
    if (isAbortError(error) || stagesRequestId.value !== currentRequestId) {
      return;
    }

    stagesError.value = getErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.ERROR')
    );
  } finally {
    if (stagesRequestId.value === currentRequestId) {
      isLoadingStages.value = false;
      stagesAbortController.value = null;
    }
  }
};

const loadEditStages = async boardId => {
  if (!boardId) return;

  const currentRequestId = editStagesRequestId.value + 1;
  editStagesRequestId.value = currentRequestId;
  editStagesAbortController.value?.abort();

  const controller = new AbortController();
  editStagesAbortController.value = controller;
  isLoadingEditStages.value = true;
  editStages.value = [];

  try {
    const response = await KanbanBoardsAPI.showBoard(boardId, {
      signal: controller.signal,
    });

    if (
      editStagesRequestId.value !== currentRequestId ||
      controller.signal.aborted
    ) {
      return;
    }

    editStages.value = response.data?.stages || [];
  } catch (error) {
    if (isAbortError(error) || editStagesRequestId.value !== currentRequestId) {
      return;
    }

    editError.value = getErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.ERROR')
    );
  } finally {
    if (editStagesRequestId.value === currentRequestId) {
      isLoadingEditStages.value = false;
      editStagesAbortController.value = null;
    }
  }
};

const loadBoards = async () => {
  const currentRequestId = boardsRequestId.value + 1;
  boardsRequestId.value = currentRequestId;
  boardsAbortController.value?.abort();

  const controller = new AbortController();
  boardsAbortController.value = controller;
  isLoadingBoards.value = true;
  boardsError.value = '';
  boards.value = [];
  selectedBoardId.value = '';
  stages.value = [];
  selectedStageId.value = '';

  try {
    const response = await KanbanBoardsAPI.getBoards({
      signal: controller.signal,
    });

    if (
      boardsRequestId.value !== currentRequestId ||
      controller.signal.aborted
    ) {
      return;
    }

    boards.value = normalizeCollection(response);
    selectedBoardId.value = activeBoards.value[0]?.id || '';

    if (selectedBoardId.value) {
      await loadStages(selectedBoardId.value);
    }
  } catch (error) {
    if (isAbortError(error) || boardsRequestId.value !== currentRequestId) {
      return;
    }

    boardsError.value = getErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.ERROR')
    );
  } finally {
    if (boardsRequestId.value === currentRequestId) {
      isLoadingBoards.value = false;
      boardsAbortController.value = null;
    }
  }
};

const openForm = () => {
  resetEditState();
  isFormOpen.value = true;
  subject.value = defaultSubject.value;
  dueAt.value = '';
  selectedLabelTitles.value = [];
  createError.value = '';
  store.dispatch('labels/get');
  loadBoards();
};

const cancelForm = () => {
  resetFormState();
  flushPendingRealtimeRefresh();
};

const onBoardChange = () => {
  selectedStageId.value = '';
  loadStages(selectedBoardId.value);
};

const onSelectBoard = board => {
  selectedBoardId.value = board.id;
  onBoardChange();
};

const onSelectStage = stage => {
  selectedStageId.value = stage.id;
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitles.value.includes(title)) return;

  selectedLabelTitles.value = [...selectedLabelTitles.value, title];
};

const onRemoveLabel = title => {
  selectedLabelTitles.value = selectedLabelTitles.value.filter(
    labelTitle => labelTitle !== title
  );
};

const dueAtPayload = () => {
  if (!dueAt.value) return null;

  const [year, month, day] = dueAt.value.split('-').map(Number);
  return new Date(year, month - 1, day, 12).toISOString();
};

const editDueAtPayload = () => {
  if (!editDueAt.value) return null;

  const [year, month, day] = editDueAt.value.split('-').map(Number);
  return new Date(year, month - 1, day, 12).toISOString();
};

const submitEdit = async card => {
  if (isSavingEdit.value) {
    hasPendingEditSave.value = true;
    return;
  }

  if (!canSaveEdit.value) return;

  isSavingEdit.value = true;
  editError.value = '';

  try {
    const response = await KanbanBoardsAPI.updateCardDetailsById(
      cardBoardId(card),
      card.id,
      {
        kanban_stage_id: editStageId.value,
        subject: editSubject.value.trim(),
        starts_at: null,
        due_at: editDueAtPayload(),
        labels: editLabelTitles.value,
      }
    );

    const updatedCard = response.data?.payload || response.data;
    if (updatedCard?.id) {
      const updatedStage = activeEditStages.value.find(
        stage => Number(stage.id) === Number(updatedCard.kanban_stage_id)
      );
      const updatedLabels = accountLabels.value.filter(label =>
        editLabelTitles.value.includes(label.title)
      );

      cards.value = cards.value.map(existingCard =>
        existingCard.id === updatedCard.id
          ? {
              ...existingCard,
              ...updatedCard,
              kanban_board: existingCard.kanban_board,
              kanban_stage: updatedStage || existingCard.kanban_stage,
              labels: updatedLabels,
            }
          : existingCard
      );
    }

    hasPendingRealtimeRefresh.value = false;
  } catch (error) {
    editError.value = getErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.UPDATE_ERROR')
    );
  } finally {
    isSavingEdit.value = false;

    if (hasPendingEditSave.value && editingCard.value) {
      hasPendingEditSave.value = false;
      submitEdit(editingCard.value);
    }
  }
};

const flushScheduledEdit = () => {
  if (!editSaveTimer.value) return;

  clearTimeout(editSaveTimer.value);
  editSaveTimer.value = null;

  if (editingCard.value) submitEdit(editingCard.value);
};

const scheduleSubmitEdit = card => {
  cancelScheduledEdit();
  editingCard.value = card;
  editSaveTimer.value = setTimeout(() => {
    editSaveTimer.value = null;
    submitEdit(card);
  }, EDIT_AUTOSAVE_DELAY);
};

const startEdit = async card => {
  flushScheduledEdit();
  resetFormState();
  resetEditState();
  editingCardId.value = card.id;
  editSubject.value = card.subject || '';
  editStageId.value = cardStageId(card) || '';
  editDueAt.value = formatDateInput(card.due_at);
  editLabelTitles.value = (card.labels || []).map(label => label.title);
  editError.value = '';
  store.dispatch('labels/get');
  await loadEditStages(cardBoardId(card));
};

const submitForm = async () => {
  if (!canSubmit.value) return;

  createAbortController.value?.abort();
  const controller = new AbortController();
  createAbortController.value = controller;
  isCreating.value = true;
  createError.value = '';

  try {
    await KanbanBoardsAPI.createConversationCard(
      props.conversationId,
      {
        card: {
          kanban_board_id: selectedBoardId.value,
          kanban_stage_id: selectedStageId.value,
          subject: subject.value.trim(),
          starts_at: null,
          due_at: dueAtPayload(),
          labels: selectedLabelTitles.value,
        },
      },
      { signal: controller.signal }
    );

    if (controller.signal.aborted) return;

    useAlert(t('CONVERSATION_SIDEBAR.KANBAN.CREATED'));
    resetFormState();
    hasPendingRealtimeRefresh.value = false;
    await loadCards();
  } catch (error) {
    if (isAbortError(error)) return;

    createError.value = getErrorMessage(
      error,
      t('CONVERSATION_SIDEBAR.KANBAN.CREATE_ERROR')
    );
  } finally {
    if (createAbortController.value === controller) {
      isCreating.value = false;
      createAbortController.value = null;
    }
  }
};

const onSelectEditStage = (card, stage) => {
  editStageId.value = stage.id;
  scheduleSubmitEdit(card);
};

const onAddEditLabel = (card, label) => {
  const title = label?.title || label;
  if (!title || editLabelTitles.value.includes(title)) return;

  editLabelTitles.value = [...editLabelTitles.value, title];
  scheduleSubmitEdit(card);
};

const onRemoveEditLabel = (card, title) => {
  editLabelTitles.value = editLabelTitles.value.filter(
    labelTitle => labelTitle !== title
  );
  scheduleSubmitEdit(card);
};

const openDeleteConfirm = card => {
  cardToDelete.value = card;
  deleteDialogRef.value?.open();
};

const confirmDeleteCard = async () => {
  const card = cardToDelete.value;
  if (!card || isDeletingCard.value) return;

  isDeletingCard.value = true;

  try {
    await KanbanBoardsAPI.deleteCardById(cardBoardId(card), card.id);

    if (editingCardId.value === card.id) {
      resetEditState();
    }
    cards.value = cards.value.filter(
      existingCard => existingCard.id !== card.id
    );

    useAlert(t('CONVERSATION_SIDEBAR.KANBAN.DELETED'));
    deleteDialogRef.value?.close();
  } catch (error) {
    useAlert(
      getErrorMessage(error, t('CONVERSATION_SIDEBAR.KANBAN.DELETE_ERROR'))
    );
  } finally {
    isDeletingCard.value = false;
    cardToDelete.value = null;
  }
};

const handleRealtimeKanbanEvent = eventPayload => {
  if (!shouldRefreshForRealtimeEvent(eventPayload)) return;

  refreshCardsFromRealtime();
};

onMounted(() => {
  emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
  loadCards();
});

watch(
  () => props.conversationId,
  () => {
    hasPendingRealtimeRefresh.value = false;
    flushScheduledEdit();
    resetFormState();
    resetEditState();
    loadCards();
  }
);

watch(
  cards,
  nextCards => {
    if (!nextCards.length || editingCardId.value !== null || isFormOpen.value) {
      return;
    }

    startEdit(nextCards[0]);
  },
  { flush: 'sync' }
);

onBeforeUnmount(() => {
  flushScheduledEdit();
  resetAbortController();
  abortFormRequests();
  abortEditRequests();
  emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleRealtimeKanbanEvent);
});
</script>

<template>
  <div class="p-3 text-sm">
    <NextButton
      v-if="!isFormOpen"
      faded
      xs
      icon="i-lucide-plus"
      class="mb-3"
      :label="t('CONVERSATION_SIDEBAR.KANBAN.ADD')"
      @click="openForm"
    />

    <form
      v-if="isFormOpen"
      class="mb-3 flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
      @submit.prevent="submitForm"
    >
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE_TITLE') }}
      </h4>

      <div class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
        </span>
        <MultiselectDropdown
          :options="activeBoards"
          :selected-item="selectedBoard"
          :has-thumbnail="false"
          :multiselector-title="t('CONVERSATION_SIDEBAR.KANBAN.BOARD')"
          :multiselector-placeholder="
            t('CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD')
          "
          :no-search-result="t('CONVERSATION_SIDEBAR.KANBAN.NO_RESULTS')"
          :input-placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SEARCH')"
          @select="onSelectBoard"
        />
      </div>
      <p v-if="isLoadingBoards" class="m-0 text-xs text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
      </p>
      <p v-else-if="boardsError" class="m-0 text-xs text-n-ruby-11">
        {{ boardsError }}
      </p>
      <p
        v-else-if="!isLoadingBoards && activeBoards.length === 0"
        class="m-0 text-xs text-n-slate-11"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY_BOARDS') }}
      </p>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.SUBJECT') }}
        </span>
        <input
          v-model="subject"
          type="text"
          class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
        />
      </label>

      <div class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
        </span>
        <MultiselectDropdown
          :options="activeStages"
          :selected-item="selectedStage"
          :has-thumbnail="false"
          :multiselector-title="t('CONVERSATION_SIDEBAR.KANBAN.STAGE')"
          :multiselector-placeholder="
            t('CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE')
          "
          :no-search-result="t('CONVERSATION_SIDEBAR.KANBAN.NO_RESULTS')"
          :input-placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SEARCH')"
          @select="onSelectStage"
        />
      </div>
      <p v-if="isLoadingStages" class="m-0 text-xs text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
      </p>
      <p v-else-if="stagesError" class="m-0 text-xs text-n-ruby-11">
        {{ stagesError }}
      </p>
      <p
        v-else-if="
          selectedBoard && !isLoadingStages && activeStages.length === 0
        "
        class="m-0 text-xs text-n-slate-11"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY_STAGES') }}
      </p>

      <KanbanDueDatePicker
        v-model="dueAt"
        :label="t('CONVERSATION_SIDEBAR.KANBAN.DUE_DATE')"
        :placeholder="t('CONVERSATION_SIDEBAR.KANBAN.CHOOSE_DATE')"
        :clear-label="t('CONVERSATION_SIDEBAR.KANBAN.CLEAR_DATE')"
      />

      <div class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.LABELS') }}
        </span>
        <Popover align="start" disable-mobile-view :show-content-border="false">
          <button
            type="button"
            data-testid="kanban-card-labels-menu"
            class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span
              aria-hidden="true"
              class="i-lucide-tags size-4 flex-shrink-0 text-n-slate-11"
            />
            <span class="min-w-0 flex-1 truncate">
              {{ selectedLabelsSummary }}
            </span>
            <span
              aria-hidden="true"
              class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
            />
          </button>

          <template #content>
            <div
              class="block visible w-80 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
            >
              <LabelDropdown
                :account-labels="accountLabels"
                :selected-labels="selectedLabelTitles"
                :allow-creation="false"
                @add="onAddLabel"
                @remove="onRemoveLabel"
              />
            </div>
          </template>
        </Popover>

        <div v-if="selectedLabels.length" class="flex flex-wrap gap-1">
          <span
            v-for="label in selectedLabels"
            :key="label.title"
            class="inline-flex items-center gap-1 rounded-md bg-n-slate-3 px-2 py-1 text-xs text-n-slate-12"
          >
            {{ label.title }}
            <button
              type="button"
              class="text-n-slate-11 hover:text-n-slate-12"
              :aria-label="label.title"
              @click="onRemoveLabel(label.title)"
            >
              <span aria-hidden="true" class="i-lucide-x size-3" />
            </button>
          </span>
        </div>
      </div>

      <p v-if="createError" class="m-0 text-xs text-n-ruby-11">
        {{ createError }}
      </p>

      <div class="flex justify-end gap-2">
        <button
          type="button"
          class="h-8 rounded-md px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2"
          @click="cancelForm"
        >
          {{ t('CONVERSATION_SIDEBAR.KANBAN.CANCEL') }}
        </button>
        <button
          type="submit"
          class="h-8 rounded-md bg-n-brand px-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!canSubmit"
        >
          {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE') }}
        </button>
      </div>
    </form>

    <p v-if="isLoading" class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
    </p>
    <p v-else-if="hasError" class="mb-0 text-n-ruby-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.ERROR') }}
    </p>
    <p v-else-if="!hasCards" class="mb-0 text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY') }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="card in cards"
        :key="card.id"
        class="group relative flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
      >
        <button
          type="button"
          class="absolute right-2 top-2 z-10 hidden size-9 items-center justify-center rounded-md text-n-slate-11 opacity-0 transition-opacity hover:bg-n-alpha-2 hover:text-n-ruby-11 group-hover:flex group-hover:opacity-100"
          :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.DELETE')"
          @click.stop="openDeleteConfirm(card)"
        >
          <span aria-hidden="true" class="i-lucide-trash-2 size-5" />
        </button>

        <form
          v-if="editingCardId === card.id"
          class="flex flex-col gap-3"
          @click.stop
          @submit.prevent="submitEdit(card)"
        >
          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
            </p>
            <p class="m-0 truncate text-sm text-n-slate-12">
              {{ card.kanban_board?.name }}
            </p>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.SUBJECT') }}
            </span>
            <input
              v-model="editSubject"
              type="text"
              class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
              @change="scheduleSubmitEdit(card)"
            />
          </label>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
            </span>
            <MultiselectDropdown
              :options="activeEditStages"
              :selected-item="selectedEditStage"
              :has-thumbnail="false"
              :multiselector-title="t('CONVERSATION_SIDEBAR.KANBAN.STAGE')"
              :multiselector-placeholder="
                t('CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE')
              "
              :no-search-result="t('CONVERSATION_SIDEBAR.KANBAN.NO_RESULTS')"
              :input-placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SEARCH')"
              @select="stage => onSelectEditStage(card, stage)"
            />
          </div>

          <p v-if="isLoadingEditStages" class="m-0 text-xs text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
          </p>
          <p
            v-else-if="!isLoadingEditStages && activeEditStages.length === 0"
            class="m-0 text-xs text-n-slate-11"
          >
            {{ t('CONVERSATION_SIDEBAR.KANBAN.EMPTY_STAGES') }}
          </p>

          <KanbanDueDatePicker
            v-model="editDueAt"
            :label="t('CONVERSATION_SIDEBAR.KANBAN.DUE_DATE')"
            :placeholder="t('CONVERSATION_SIDEBAR.KANBAN.CHOOSE_DATE')"
            :clear-label="t('CONVERSATION_SIDEBAR.KANBAN.CLEAR_DATE')"
            @change="scheduleSubmitEdit(card)"
          />

          <div class="flex flex-col gap-2">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.LABELS') }}
            </span>
            <Popover
              align="start"
              disable-mobile-view
              :show-content-border="false"
            >
              <button
                type="button"
                data-testid="kanban-card-labels-menu"
                class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
              >
                <span
                  aria-hidden="true"
                  class="i-lucide-tags size-4 flex-shrink-0 text-n-slate-11"
                />
                <span class="min-w-0 flex-1 truncate">
                  {{ editLabelsSummary }}
                </span>
                <span
                  aria-hidden="true"
                  class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
                />
              </button>

              <template #content>
                <div
                  class="block visible w-80 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
                >
                  <LabelDropdown
                    :account-labels="accountLabels"
                    :selected-labels="editLabelTitles"
                    :allow-creation="false"
                    @add="label => onAddEditLabel(card, label)"
                    @remove="title => onRemoveEditLabel(card, title)"
                  />
                </div>
              </template>
            </Popover>

            <div v-if="editLabelTitles.length" class="flex flex-wrap gap-1">
              <span
                v-for="title in editLabelTitles"
                :key="title"
                class="inline-flex items-center gap-1 rounded-md bg-n-slate-3 px-2 py-1 text-xs text-n-slate-12"
              >
                {{ title }}
                <button
                  type="button"
                  class="text-n-slate-11 hover:text-n-slate-12"
                  :aria-label="title"
                  @click="onRemoveEditLabel(card, title)"
                >
                  <span aria-hidden="true" class="i-lucide-x size-3" />
                </button>
              </span>
            </div>
          </div>

          <p v-if="editError" class="m-0 text-xs text-n-ruby-11">
            {{ editError }}
          </p>

          <p v-if="isSavingEdit" class="m-0 text-right text-xs text-n-slate-11">
            {{ t('CONVERSATION_SIDEBAR.KANBAN.SAVING') }}
          </p>
        </form>

        <div
          v-else
          role="button"
          tabindex="0"
          data-testid="kanban-linked-card"
          class="flex cursor-pointer flex-col gap-3 rounded-md outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="startEdit(card)"
          @keydown.enter.prevent="startEdit(card)"
          @keydown.space.prevent="startEdit(card)"
        >
          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
            </p>
            <p class="m-0 truncate text-sm text-n-slate-12">
              {{ card.kanban_board?.name }}
            </p>
          </div>

          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.SUBJECT') }}
            </p>
            <p class="m-0 truncate text-sm text-n-slate-12">
              {{ card.subject }}
            </p>
          </div>

          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
            </p>
            <div
              class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12"
            >
              <span
                v-if="card.kanban_stage?.color"
                class="size-2 flex-shrink-0 rounded-full"
                :class="stageColorClass(card.kanban_stage.color)"
                aria-hidden="true"
              />
              <span class="min-w-0 truncate">
                {{ card.kanban_stage?.name }}
              </span>
            </div>
          </div>

          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.DUE_DATE') }}
            </p>
            <p class="m-0 truncate text-sm text-n-slate-12">
              {{ formatDueAt(card.due_at) }}
            </p>
          </div>

          <div class="min-w-0">
            <p class="mb-1 text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.LABELS') }}
            </p>
            <div v-if="card.labels?.length" class="flex flex-wrap gap-1">
              <span
                v-for="label in card.labels"
                :key="label.id || label.title"
                class="inline-flex min-w-0 items-center gap-1 rounded-full bg-n-slate-3 px-2 py-1 text-xs text-n-slate-12"
              >
                <span
                  class="size-2 flex-shrink-0 rounded-full"
                  :style="{ backgroundColor: label.color }"
                  aria-hidden="true"
                />
                <span class="truncate">{{ label.title }}</span>
              </span>
            </div>
            <p v-else class="m-0 text-sm text-n-slate-11">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.NO_LABELS') }}
            </p>
          </div>
        </div>
      </li>
    </ul>

    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_TITLE')"
      :description="t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_DESCRIPTION')"
      :confirm-button-label="
        t('CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_BUTTON')
      "
      :is-loading="isDeletingCard"
      @confirm="confirmDeleteCard"
    />
  </div>
</template>
