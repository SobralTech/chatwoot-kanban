<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { formatDateInput, toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanCardAdditionalDataTab from '../KanbanCardAdditionalDataTab.vue';
import KanbanCardOverviewTab from './tabs/KanbanCardOverviewTab.vue';
import KanbanCardItemsTab from './tabs/KanbanCardItemsTab.vue';
import KanbanCardContextRail from './KanbanCardContextRail.vue';
import KanbanCardStatusBadge from '../KanbanCardStatusBadge.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  lostStageId: {
    type: Number,
    default: null,
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  customFields: {
    type: Array,
    default: () => [],
  },
  stages: {
    type: Array,
    default: () => [],
  },
  moveToStage: {
    type: Function,
    default: null,
  },
});

const emit = defineEmits([
  'close',
  'updated',
  'openConversation',
  'removeCard',
  'moveToStage',
]);

const TAB_KEYS = ['general', 'products', 'additional_data'];

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');

const activeTabIndex = ref(0);
const loadedTabKeys = ref(['general']);
const activeTabKey = computed(() => TAB_KEYS[activeTabIndex.value]);
const card = ref(null);
const panelRef = ref(null);
const previousActiveElement = ref(null);
const stageSelection = ref('');
const isMovingStage = ref(false);

const isTerminalStage = stage =>
  Number(stage.id) === Number(props.wonStageId) ||
  Number(stage.id) === Number(props.lostStageId);
const stageOptions = computed(() => {
  const options = props.stages
    .filter(stage => !isTerminalStage(stage))
    .map(stage => ({ value: stage.id, label: stage.name }));
  const currentStage = props.stages.find(
    stage => Number(stage.id) === Number(card.value?.kanbanStageId)
  );

  if (
    currentStage &&
    !options.some(option => Number(option.value) === Number(currentStage.id))
  ) {
    options.push({
      value: currentStage.id,
      label: currentStage.name,
      disabled: true,
    });
  }

  return options;
});

watch(
  () => card.value?.kanbanStageId,
  stageId => {
    if (!isMovingStage.value) stageSelection.value = stageId || '';
  },
  { immediate: true }
);

const onStageChanged = async stageId => {
  const targetStageId = Number(stageId);
  const currentStageId = Number(card.value?.kanbanStageId);
  if (
    !card.value ||
    !targetStageId ||
    targetStageId === currentStageId ||
    isTerminalStage(
      props.stages.find(stage => Number(stage.id) === targetStageId) || {}
    )
  ) {
    stageSelection.value = card.value?.kanbanStageId || '';
    return;
  }

  isMovingStage.value = true;
  stageSelection.value = targetStageId;
  const moved = props.moveToStage
    ? await props.moveToStage(card.value, targetStageId)
    : (emit('moveToStage', card.value, targetStageId), true);

  if (moved !== false) {
    card.value = { ...card.value, kanbanStageId: targetStageId };
  } else {
    stageSelection.value = card.value.kanbanStageId || '';
  }
  isMovingStage.value = false;
};

const focusableSelector =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';
const focusPanel = () => panelRef.value?.focus();
let saveCard;

const subject = ref('');
const description = ref('');
const dueAt = ref('');
const priority = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingLabels = ref(false);
const isLoadingAssignees = ref(false);
const loadError = ref('');
const saveError = ref('');
const labelsLoadError = ref('');
const assigneesLoadError = ref('');
const subjectError = ref('');
const selectedLabelTitles = ref([]);
const assignedUsers = ref([]);
const assignableUsers = ref([]);

const productsTotalValue = ref(null);
const totalValue = computed(
  () => productsTotalValue.value ?? Number(card.value?.value || 0)
);
const onProductsTotalChanged = value => {
  productsTotalValue.value = value;
};

const cardDisplayId = computed(() => card.value?.id || props.cardId);
const selectedAssigneeIds = computed(() =>
  assignedUsers.value.map(user => user.id)
);
const selectedLabelTitleSet = computed(
  () => new Set(selectedLabelTitles.value)
);

const additionalDataTabRef = ref(null);

const initial = ref({
  subject: '',
  description: '',
  dueAt: '',
  priority: '',
  labels: [],
  assigneeIds: [],
});
const savedAt = ref(null);
const currentTime = ref(Date.now());
let savedTimeTimer = null;

const normalizeIds = ids =>
  ids.map(value => Number(value)).sort((a, b) => a - b);
const buildFormState = () => ({
  subject: subject.value,
  description: description.value,
  dueAt: dueAt.value,
  priority: priority.value,
  labels: [...selectedLabelTitles.value].sort(),
  assigneeIds: normalizeIds(selectedAssigneeIds.value),
});
const captureSnapshot = () => {
  initial.value = buildFormState();
  savedAt.value = Date.now();
};
const dirtyFields = computed(() => {
  const current = buildFormState();

  return {
    subject: current.subject !== initial.value.subject,
    description: current.description !== initial.value.description,
    dueAt: current.dueAt !== initial.value.dueAt,
    priority: current.priority !== initial.value.priority,
    labels: current.labels.join('|') !== initial.value.labels.join('|'),
    assignees:
      current.assigneeIds.join('|') !== initial.value.assigneeIds.join('|'),
    additionalData: !!additionalDataTabRef.value?.hasUnsavedChanges,
  };
});
const hasGeneralChanges = computed(() =>
  Object.entries(dirtyFields.value).some(
    ([field, isDirty]) => field !== 'additionalData' && isDirty
  )
);
const unsavedFields = computed(() => {
  const fields = [];

  if (dirtyFields.value.subject)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE'));
  if (dirtyFields.value.description)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION'));
  if (dirtyFields.value.priority)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY'));
  if (dirtyFields.value.dueAt)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE'));
  if (dirtyFields.value.labels)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.LABELS'));
  if (dirtyFields.value.assignees)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE'));
  if (dirtyFields.value.additionalData)
    fields.push(t('KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA'));

  return fields;
});
const hasUnsavedChanges = computed(
  () => !!card.value && Object.values(dirtyFields.value).some(Boolean)
);
const savedTimeLabel = computed(() => {
  if (!savedAt.value) return '';

  const elapsedSeconds = Math.max(
    0,
    (currentTime.value - savedAt.value) / 1000
  );
  const relativeTime = new Intl.RelativeTimeFormat(undefined, {
    numeric: 'auto',
  });

  if (elapsedSeconds < 60) return relativeTime.format(0, 'second');
  if (elapsedSeconds < 3600) {
    return relativeTime.format(-Math.floor(elapsedSeconds / 60), 'minute');
  }
  if (elapsedSeconds < 86400) {
    return relativeTime.format(-Math.floor(elapsedSeconds / 3600), 'hour');
  }

  return relativeTime.format(-Math.floor(elapsedSeconds / 86400), 'day');
});
const tabItems = computed(() => [
  {
    label: `${t('KANBAN.OPPORTUNITY_DETAILS.TABS.GENERAL')}${
      hasGeneralChanges.value ? ' •' : ''
    }`,
  },
  { label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS') },
  {
    label: `${t('KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA')}${
      dirtyFields.value.additionalData ? ' •' : ''
    }`,
  },
]);
const onTabChanged = tab => {
  const index = tabItems.value.findIndex(item => item.label === tab.label);
  if (index === -1) return;

  activeTabIndex.value = index;
  loadedTabKeys.value = [...new Set([...loadedTabKeys.value, TAB_KEYS[index]])];
};

const normalizeCard = payload => ({
  ...payload,
  accountId: payload.accountId ?? payload.account_id,
  kanbanBoardId: payload.kanbanBoardId ?? payload.kanban_board_id,
  kanbanStageId: payload.kanbanStageId ?? payload.kanban_stage_id,
  kanbanReasonId: payload.kanbanReasonId ?? payload.kanban_reason_id,
  conversationId: payload.conversationId ?? payload.conversation_id,
  dueAt: payload.dueAt ?? payload.due_at,
});

const getErrorMessage = (error, fallback) => {
  const errors = error?.response?.data?.errors;

  if (Array.isArray(errors)) return errors.join(', ');
  if (typeof errors === 'string') return errors;
  if (errors && typeof errors === 'object') {
    return Object.values(errors).flat().join(', ');
  }

  return error?.response?.data?.message || error?.message || fallback;
};

const setFormState = payload => {
  card.value = normalizeCard(payload);
  subject.value = card.value.subject || '';
  description.value = card.value.description || '';
  dueAt.value = formatDateInput(card.value.dueAt);
  priority.value = card.value.priority || '';
};
const setEmbeddedContext = payload => {
  const labels = Array.isArray(payload.labels) ? payload.labels : [];
  const assignees = Array.isArray(payload.assignees) ? payload.assignees : [];
  const assignable = Array.isArray(payload.assignable_users)
    ? payload.assignable_users
    : [];

  selectedLabelTitles.value = labels.map(label => label.title || label);
  assignedUsers.value = assignees;
  assignableUsers.value = assignable;
};

const getLabelsPayload = response =>
  response?.data?.payload || response?.data || [];

const onToggleAssignee = user => {
  assignedUsers.value = selectedAssigneeIds.value.includes(user.id)
    ? assignedUsers.value.filter(existing => existing.id !== user.id)
    : [...assignedUsers.value, user];
};

const loadCard = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.showCardById(
      props.boardId,
      props.cardId
    );
    const cardPayload = response.data || {};
    setFormState(cardPayload);
    setEmbeddedContext(cardPayload);
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const onChangeCardStatus = async ({ targetStageId, reasonId, reopen }) => {
  try {
    const response = reopen
      ? await KanbanBoardsAPI.reopenCardById(props.boardId, props.cardId)
      : await KanbanBoardsAPI.updateCardById(props.boardId, props.cardId, {
          card: {
            kanban_stage_id: targetStageId,
            kanban_reason_id: reasonId || null,
          },
        });
    const updatedCard = normalizeCard(response.data || {});
    const nextCard = {
      ...(card.value || {}),
      kanbanStageId:
        updatedCard.kanbanStageId ??
        (reopen ? card.value?.kanbanStageId : targetStageId),
      kanbanReasonId:
        updatedCard.kanbanReasonId ?? (reopen ? null : reasonId || null),
    };

    card.value = nextCard;
    emit('updated', nextCard);
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
  }
};

saveCard = async () => {
  if (isSaving.value || !hasUnsavedChanges.value) return false;

  const trimmedSubject = subject.value.trim();
  subjectError.value = '';
  saveError.value = '';

  if (!trimmedSubject) {
    subjectError.value = t('KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE');
    return false;
  }

  isSaving.value = true;

  try {
    const payload = {
      subject: trimmedSubject,
      description: description.value.trim() ? description.value : null,
      due_at: toIso8601(dueAt.value),
      priority: priority.value || null,
    };
    let cardResponse;

    try {
      cardResponse = await KanbanBoardsAPI.updateCardDetailsById(
        props.boardId,
        props.cardId,
        payload
      );
    } catch {
      saveError.value = t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD');
      return false;
    }

    const updatedCard = normalizeCard(cardResponse.data || {});
    card.value = { ...(card.value || {}), ...updatedCard };
    setFormState(updatedCard);

    let labelsResponse;
    try {
      labelsResponse = await KanbanBoardsAPI.updateCardLabels(
        props.boardId,
        props.cardId,
        selectedLabelTitles.value
      );
    } catch {
      saveError.value = t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_LABELS');
      return false;
    }
    selectedLabelTitles.value = getLabelsPayload(labelsResponse).map(
      label => label.title || label
    );

    let assigneesResponse;
    try {
      assigneesResponse = await KanbanBoardsAPI.updateCardAssignees(
        props.boardId,
        props.cardId,
        selectedAssigneeIds.value
      );
    } catch {
      saveError.value = t(
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_ASSIGNEES'
      );
      return false;
    }
    assignedUsers.value = assigneesResponse?.data?.payload || [];
    assignableUsers.value =
      assigneesResponse?.data?.assignable_users || assignableUsers.value;

    if (additionalDataTabRef.value?.hasUnsavedChanges) {
      let additionalDataSaved = false;

      try {
        additionalDataSaved =
          await additionalDataTabRef.value.saveFieldValues();
      } catch {
        additionalDataSaved = false;
      }

      if (!additionalDataSaved) {
        saveError.value = t(
          'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_FIELDS'
        );
        return false;
      }
    }

    captureSnapshot();
    emit('updated', card.value);
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS'));
    return true;
  } finally {
    isSaving.value = false;
  }
};
const onDocumentKeydown = event => {
  if (!panelRef.value) return;

  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 's') {
    event.preventDefault();
    saveCard();
    return;
  }
  if (event.key === 'Escape') {
    event.preventDefault();
    emit('close');
    return;
  }

  if (event.key !== 'Tab') return;

  const focusableElements = [
    ...panelRef.value.querySelectorAll(focusableSelector),
  ];
  if (!focusableElements.length) {
    event.preventDefault();
    focusPanel();
    return;
  }

  const firstElement = focusableElements[0];
  const lastElement = focusableElements.at(-1);
  if (!panelRef.value.contains(document.activeElement)) {
    event.preventDefault();
    (event.shiftKey ? lastElement : firstElement).focus();
  } else if (event.shiftKey && document.activeElement === firstElement) {
    event.preventDefault();
    lastElement.focus();
  } else if (!event.shiftKey && document.activeElement === lastElement) {
    event.preventDefault();
    firstElement.focus();
  }
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitleSet.value.has(title)) return;

  selectedLabelTitles.value = [...selectedLabelTitles.value, title];
};

const onRemoveLabel = title => {
  if (!title || !selectedLabelTitleSet.value.has(title)) return;

  selectedLabelTitles.value = selectedLabelTitles.value.filter(
    selectedTitle => selectedTitle !== title
  );
};

const copyCardId = async () => {
  await copyTextToClipboard(cardDisplayId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const openConversation = () => {
  if (!card.value?.conversationId) return;

  emit('openConversation', card.value);
};

const loadOpportunityData = async () => {
  await loadCard();
  if (card.value) captureSnapshot();
};

onMounted(() => {
  previousActiveElement.value = document.activeElement;
  document.addEventListener('keydown', onDocumentKeydown);
  savedTimeTimer = setInterval(() => {
    currentTime.value = Date.now();
  }, 60000);
  nextTick(focusPanel);
  loadOpportunityData();
});

onUnmounted(() => {
  document.removeEventListener('keydown', onDocumentKeydown);
  clearInterval(savedTimeTimer);
  if (previousActiveElement.value?.isConnected) {
    previousActiveElement.value.focus();
  }
});

defineExpose({ saveCard, hasUnsavedChanges, unsavedFields });
</script>

<template>
  <div
    data-testid="kanban-opportunity-panel-overlay"
    class="fixed inset-0 z-[9990] flex bg-n-alpha-black2 backdrop-blur-[4px]"
    @mousedown.self="emit('close')"
  >
    <aside
      ref="panelRef"
      data-testid="kanban-opportunity-panel"
      role="dialog"
      aria-modal="true"
      aria-labelledby="kanban-opportunity-title"
      tabindex="-1"
      class="flex h-full w-full max-w-full flex-col overflow-hidden border-n-weak bg-n-background shadow-xl outline-none ltr:ml-auto ltr:border-l rtl:mr-auto rtl:border-r md:w-[min(56rem,70vw)]"
    >
      <header
        class="flex flex-none items-start justify-between gap-4 border-b border-n-weak px-4 py-4"
      >
        <div class="min-w-0 flex-1">
          <div class="flex min-w-0 items-center gap-2">
            <h2
              id="kanban-opportunity-title"
              data-testid="kanban-opportunity-title"
              class="mb-0 truncate text-base font-semibold text-n-slate-12"
            >
              {{ card?.subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE') }}
            </h2>
            <span
              v-if="hasUnsavedChanges"
              data-testid="kanban-opportunity-unsaved-indicator"
              class="inline-flex flex-shrink-0 items-center gap-1.5 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
            >
              <span class="size-1.5 rounded-full bg-n-amber-9" />
              {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_INDICATOR') }}
            </span>
          </div>
          <div
            v-if="card"
            class="mt-2 flex min-w-0 flex-wrap items-center gap-2"
          >
            <KanbanCardStatusBadge
              v-if="wonStageId && lostStageId"
              :kanban-stage-id="card.kanbanStageId"
              :won-stage-id="wonStageId"
              :lost-stage-id="lostStageId"
              :reasons="reasons"
              :lost-reason-required="lostReasonRequired"
              @change="onChangeCardStatus"
            />
            <Select
              v-if="stageOptions.length"
              v-model="stageSelection"
              data-testid="kanban-opportunity-stage-select"
              :options="stageOptions"
              :disabled="isMovingStage"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.MOVE_TO_STAGE')"
              @update:model-value="onStageChanged"
            />
          </div>
        </div>
        <div v-if="cardDisplayId" class="flex flex-shrink-0 items-center gap-1">
          <span
            data-testid="kanban-opportunity-card-id"
            class="text-sm font-medium text-n-slate-11"
          >
            {{ t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID', { id: cardDisplayId }) }}
          </span>
          <Popover align="end" disable-mobile-view :show-content-border="false">
            <button
              type="button"
              data-testid="kanban-opportunity-more-actions"
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.MORE_ACTIONS')"
            >
              <i class="i-lucide-ellipsis-vertical size-4" />
            </button>
            <template #content>
              <div class="grid min-w-40 gap-1 rounded-lg p-1">
                <button
                  type="button"
                  data-testid="kanban-opportunity-copy-card-id"
                  class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID')"
                  @click="copyCardId"
                >
                  <i class="i-lucide-copy size-4" />
                  {{ t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID') }}
                </button>
                <button
                  v-if="card"
                  type="button"
                  data-testid="kanban-opportunity-remove-card"
                  class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-ruby-11 hover:bg-n-ruby-2"
                  :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
                  :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
                  @click="emit('removeCard', card)"
                >
                  <i class="i-lucide-trash size-4" />
                  {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
                </button>
              </div>
            </template>
          </Popover>
          <button
            type="button"
            data-testid="kanban-opportunity-close"
            class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
            :title="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
            @click="emit('close')"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </div>
      </header>

      <div class="flex-none border-b border-n-weak px-4 py-3">
        <TabBar
          :tabs="tabItems"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <div class="min-h-0 flex-1 overflow-auto px-4 py-4">
        <p
          v-if="isLoading"
          data-testid="kanban-opportunity-loading"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.LOADING') }}
        </p>

        <p
          v-else-if="loadError"
          data-testid="kanban-opportunity-load-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ loadError }}
        </p>

        <template v-else-if="card">
          <div
            data-testid="kanban-opportunity-layout"
            class="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(16rem,18rem)]"
          >
            <div class="min-w-0">
              <section
                v-show="activeTabKey === 'general'"
                data-testid="kanban-opportunity-general-tab"
              >
                <form
                  data-testid="kanban-opportunity-form"
                  class="grid gap-5"
                  @submit.prevent="saveCard"
                >
                  <KanbanCardOverviewTab
                    v-model:subject="subject"
                    v-model:description="description"
                    v-model:priority="priority"
                    :subject-error="subjectError"
                    @clear-subject-error="subjectError = ''"
                  />
                </form>
              </section>

              <template v-if="loadedTabKeys.includes('products')">
                <KanbanCardItemsTab
                  v-show="activeTabKey === 'products'"
                  :board-id="boardId"
                  :card-id="cardId"
                  @total-changed="onProductsTotalChanged"
                />
              </template>
              <template v-if="loadedTabKeys.includes('additional_data')">
                <section
                  v-show="activeTabKey === 'additional_data'"
                  data-testid="kanban-opportunity-additional-data-tab"
                >
                  <KanbanCardAdditionalDataTab
                    ref="additionalDataTabRef"
                    :board-id="boardId"
                    :card-id="cardId"
                    :custom-fields="customFields"
                  />
                </section>
              </template>
            </div>

            <KanbanCardContextRail
              v-model:due-at="dueAt"
              :card="card"
              :account-labels="accountLabels"
              :selected-label-titles="selectedLabelTitles"
              :is-loading-labels="isLoadingLabels"
              :labels-load-error="labelsLoadError"
              :assigned-users="assignedUsers"
              :assignable-users="assignableUsers"
              :is-loading-assignees="isLoadingAssignees"
              :assignees-load-error="assigneesLoadError"
              :total-value="totalValue"
              @add-label="onAddLabel"
              @remove-label="onRemoveLabel"
              @toggle-assignee="onToggleAssignee"
              @open-conversation="openConversation"
            />
          </div>
          <p
            v-if="saveError"
            data-testid="kanban-opportunity-save-error"
            class="mb-0 mt-4 text-sm text-n-ruby-11"
          >
            {{ saveError }}
          </p>
        </template>
      </div>

      <div
        data-testid="kanban-opportunity-savebar"
        class="flex flex-none items-center justify-between gap-3 border-t border-n-weak bg-n-background px-4 py-3"
      >
        <p
          data-testid="kanban-opportunity-save-state"
          class="mb-0 text-sm text-n-slate-11"
        >
          <span v-if="isSaving">{{
            t('KANBAN.OPPORTUNITY_DETAILS.SAVING_STATE')
          }}</span>
          <span v-else-if="hasUnsavedChanges">{{
            t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_STATE')
          }}</span>
          <span v-else-if="savedAt">{{
            t('KANBAN.OPPORTUNITY_DETAILS.SAVED_AGO', {
              time: savedTimeLabel,
            })
          }}</span>
        </p>
        <div class="flex items-center justify-end gap-3">
          <NextButton
            type="button"
            outline
            slate
            sm
            data-testid="kanban-opportunity-cancel"
            :label="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL')"
            @click="emit('close')"
          />
          <NextButton
            type="button"
            sm
            data-testid="kanban-opportunity-save"
            :label="
              isSaving
                ? t('KANBAN.OPPORTUNITY_DETAILS.SAVING')
                : t('KANBAN.OPPORTUNITY_DETAILS.SAVE_CHANGES')
            "
            :title="
              !hasUnsavedChanges
                ? t('KANBAN.OPPORTUNITY_DETAILS.NO_CHANGES')
                : undefined
            "
            :disabled="isSaving || !hasUnsavedChanges"
            :is-loading="isSaving"
            @click="saveCard"
          />
        </div>
      </div>
    </aside>
  </div>
</template>
