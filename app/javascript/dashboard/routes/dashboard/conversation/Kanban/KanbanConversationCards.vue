<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import { messageStamp } from 'shared/helpers/timeHelper';

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

const hasCards = computed(() => cards.value.length > 0);
const activeBoards = computed(() =>
  boards.value.filter(board => board.active !== false)
);
const activeStages = computed(() =>
  stages.value.filter(stage => stage.active !== false)
);
const selectedBoard = computed(() =>
  activeBoards.value.find(
    board => Number(board.id) === Number(selectedBoardId.value)
  )
);
const selectedLabels = computed(() =>
  accountLabels.value.filter(label =>
    selectedLabelTitles.value.includes(label.title)
  )
);
const canSubmit = computed(
  () => selectedBoardId.value && selectedStageId.value && !isCreating.value
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

const stageColorClass = color => {
  const colorClasses = {
    blue: 'bg-n-blue-9',
    teal: 'bg-n-teal-9',
    amber: 'bg-n-amber-9',
    ruby: 'bg-n-ruby-9',
    iris: 'bg-n-iris-9',
    violet: 'bg-n-violet-9',
  };

  return colorClasses[color] || 'bg-n-slate-9';
};

const formatDueAt = value => {
  if (!value) return t('CONVERSATION_SIDEBAR.KANBAN.NOT_SET');

  return messageStamp(new Date(value).getTime() / 1000, 'LLL d, yyyy h:mm a');
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
    }
  }
};

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
  isFormOpen.value = true;
  subject.value = defaultSubject.value;
  dueAt.value = '';
  selectedLabelTitles.value = [];
  createError.value = '';
  store.dispatch('labels/get');
  loadBoards();
};

const onBoardChange = () => {
  selectedStageId.value = '';
  loadStages(selectedBoardId.value);
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

  return new Date(dueAt.value).toISOString();
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
          due_at: dueAtPayload(),
          labels: selectedLabelTitles.value,
        },
      },
      { signal: controller.signal }
    );

    if (controller.signal.aborted) return;

    useAlert(t('CONVERSATION_SIDEBAR.KANBAN.CREATED'));
    resetFormState();
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

onMounted(loadCards);

watch(
  () => props.conversationId,
  () => {
    resetFormState();
    loadCards();
  }
);

onBeforeUnmount(() => {
  resetAbortController();
  abortFormRequests();
});
</script>

<template>
  <div class="p-3 text-sm">
    <button
      v-if="!isFormOpen"
      type="button"
      class="mb-3 inline-flex h-8 items-center rounded-md border border-n-strong px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
      @click="openForm"
    >
      {{ t('CONVERSATION_SIDEBAR.KANBAN.ADD') }}
    </button>

    <form
      v-if="isFormOpen"
      class="mb-3 flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
      @submit.prevent="submitForm"
    >
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE_TITLE') }}
      </h4>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
        </span>
        <select
          v-model="selectedBoardId"
          class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
          :disabled="isLoadingBoards || activeBoards.length === 0"
          @change="onBoardChange"
        >
          <option value="">
            {{ t('CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD') }}
          </option>
          <option
            v-for="board in activeBoards"
            :key="board.id"
            :value="board.id"
          >
            {{ board.name }}
          </option>
        </select>
      </label>
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

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
        </span>
        <select
          v-model="selectedStageId"
          class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
          :disabled="isLoadingStages || activeStages.length === 0"
        >
          <option value="">
            {{ t('CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE') }}
          </option>
          <option
            v-for="stage in activeStages"
            :key="stage.id"
            :value="stage.id"
          >
            {{ stage.name }}
          </option>
        </select>
      </label>
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

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.DUE_DATE') }}
        </span>
        <input
          v-model="dueAt"
          type="datetime-local"
          class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
        />
      </label>

      <label class="flex flex-col gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.LABELS') }}
        </span>
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
        <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-2">
          <LabelDropdown
            :account-labels="accountLabels"
            :selected-labels="selectedLabelTitles"
            :allow-creation="false"
            @add="onAddLabel"
            @remove="onRemoveLabel"
          />
        </div>
      </label>

      <p v-if="createError" class="m-0 text-xs text-n-ruby-11">
        {{ createError }}
      </p>

      <div class="flex justify-end gap-2">
        <button
          type="button"
          class="h-8 rounded-md px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2"
          @click="resetFormState"
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
        class="flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
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
          <div class="flex min-w-0 items-center gap-2 text-sm text-n-slate-12">
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
      </li>
    </ul>
  </div>
</template>
