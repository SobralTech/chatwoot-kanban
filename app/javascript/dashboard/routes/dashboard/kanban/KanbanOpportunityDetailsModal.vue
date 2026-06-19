<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import KanbanDueDatePicker from './KanbanDueDatePicker.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['close', 'updated', 'openConversation']);

const { t } = useI18n();
const store = useStore();
const accountLabels = useMapGetter('labels/getLabels');

const card = ref(null);
const subject = ref('');
const description = ref('');
const dueAt = ref('');
const priority = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingLabels = ref(false);
const isSavingLabels = ref(false);
const isLoadingAssignees = ref(false);
const isSavingAssignees = ref(false);
const loadError = ref('');
const saveError = ref('');
const labelsLoadError = ref('');
const labelsSaveError = ref('');
const assigneesLoadError = ref('');
const assigneesSaveError = ref('');
const subjectError = ref('');
const selectedLabelTitles = ref([]);
const assignedUsers = ref([]);
const assignableUsers = ref([]);

const modalTitle = computed(() => t('KANBAN.OPPORTUNITY_DETAILS.TITLE'));
const cardDisplayId = computed(() => card.value?.id || props.cardId);
const hasConversation = computed(() => !!card.value?.conversationId);
const inboxName = computed(
  () =>
    card.value?.inbox?.name ||
    card.value?.conversation?.inbox?.name ||
    t('KANBAN.OPPORTUNITY_DETAILS.NO_INBOX')
);
const selectedAssigneeIds = computed(() =>
  assignedUsers.value.map(user => user.id)
);
const assigneesSummary = computed(() => {
  if (!assignedUsers.value.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED');
  }

  return assignedUsers.value.map(user => user.name).join(', ');
});
const priorityOptions = computed(() => [
  { value: '', label: t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY_NONE') },
  { value: 'urgent', label: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
  { value: 'high', label: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
  { value: 'medium', label: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
  { value: 'low', label: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
]);
const contactName = computed(
  () =>
    card.value?.contact?.name ||
    card.value?.contact?.email ||
    card.value?.contact?.phone_number ||
    t('KANBAN.OPPORTUNITY_DETAILS.NO_CONTACT')
);
const selectedLabelTitleSet = computed(
  () => new Set(selectedLabelTitles.value)
);
const selectedLabels = computed(() =>
  selectedLabelTitles.value.map(title => {
    const accountLabel = accountLabels.value.find(
      label => label.title === title
    );
    return accountLabel || { title };
  })
);
const selectedLabelsSummary = computed(() => {
  if (!selectedLabelTitles.value.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED');
  }

  return selectedLabelTitles.value.join(', ');
});

const normalizeCard = payload => ({
  ...payload,
  accountId: payload.accountId ?? payload.account_id,
  kanbanBoardId: payload.kanbanBoardId ?? payload.kanban_board_id,
  kanbanStageId: payload.kanbanStageId ?? payload.kanban_stage_id,
  conversationId: payload.conversationId ?? payload.conversation_id,
  dueAt: payload.dueAt ?? payload.due_at,
});

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

const toIso8601 = value => {
  if (!value) return null;

  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day, 12).toISOString();
};

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

const getLabelsPayload = response =>
  response?.data?.payload || response?.data || [];

const loadLabels = async () => {
  isLoadingLabels.value = true;
  labelsLoadError.value = '';

  try {
    const [assignedLabelsResponse] = await Promise.all([
      KanbanBoardsAPI.getCardLabels(props.boardId, props.cardId),
      store.dispatch('labels/get'),
    ]);
    selectedLabelTitles.value = getLabelsPayload(assignedLabelsResponse).map(
      label => label.title || label
    );
  } catch (error) {
    labelsLoadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_LABELS_ERROR')
    );
  } finally {
    isLoadingLabels.value = false;
  }
};

const loadAssignees = async () => {
  isLoadingAssignees.value = true;
  assigneesLoadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getCardAssignees(
      props.boardId,
      props.cardId
    );
    assignedUsers.value = response?.data?.payload || [];
    assignableUsers.value = response?.data?.assignable_users || [];
  } catch (error) {
    assigneesLoadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ASSIGNEES_ERROR')
    );
  } finally {
    isLoadingAssignees.value = false;
  }
};

const saveAssignees = async nextIds => {
  if (isSavingAssignees.value) return;

  isSavingAssignees.value = true;
  assigneesSaveError.value = '';
  const previousUsers = [...assignedUsers.value];

  try {
    const response = await KanbanBoardsAPI.updateCardAssignees(
      props.boardId,
      props.cardId,
      nextIds
    );
    assignedUsers.value = response?.data?.payload || [];
    assignableUsers.value =
      response?.data?.assignable_users || assignableUsers.value;
  } catch (error) {
    assignedUsers.value = previousUsers;
    assigneesSaveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_ASSIGNEES_ERROR')
    );
  } finally {
    isSavingAssignees.value = false;
  }
};

const onToggleAssignee = user => {
  const nextIds = selectedAssigneeIds.value.includes(user.id)
    ? selectedAssigneeIds.value.filter(id => id !== user.id)
    : [...selectedAssigneeIds.value, user.id];

  saveAssignees(nextIds);
};

const loadCard = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.showCardById(
      props.boardId,
      props.cardId
    );
    setFormState(response.data || {});
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const saveCard = async () => {
  if (isSaving.value) return;

  const trimmedSubject = subject.value.trim();
  subjectError.value = '';
  saveError.value = '';

  if (!trimmedSubject) {
    subjectError.value = t('KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE');
    return;
  }

  isSaving.value = true;

  try {
    const payload = {
      subject: trimmedSubject,
      description: description.value.trim() ? description.value : null,
      starts_at: null,
      due_at: toIso8601(dueAt.value),
      priority: priority.value || null,
    };
    const response = await KanbanBoardsAPI.updateCardDetailsById(
      props.boardId,
      props.cardId,
      payload
    );
    const updatedCard = normalizeCard(response.data || {});
    setFormState(updatedCard);
    emit('updated', updatedCard);
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS'));
  } catch (error) {
    saveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const saveLabels = async nextTitles => {
  if (isSavingLabels.value) return;

  isSavingLabels.value = true;
  labelsSaveError.value = '';
  const previousTitles = [...selectedLabelTitles.value];
  selectedLabelTitles.value = nextTitles;

  try {
    const response = await KanbanBoardsAPI.updateCardLabels(
      props.boardId,
      props.cardId,
      nextTitles
    );
    selectedLabelTitles.value = getLabelsPayload(response).map(
      label => label.title || label
    );
  } catch (error) {
    selectedLabelTitles.value = previousTitles;
    labelsSaveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_LABELS_ERROR')
    );
  } finally {
    isSavingLabels.value = false;
  }
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitleSet.value.has(title)) return;

  saveLabels([...selectedLabelTitles.value, title]);
};

const onRemoveLabel = title => {
  if (!title || !selectedLabelTitleSet.value.has(title)) return;

  saveLabels(
    selectedLabelTitles.value.filter(selectedTitle => selectedTitle !== title)
  );
};

const copyCardId = async () => {
  await copyTextToClipboard(cardDisplayId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const openConversation = () => {
  if (!hasConversation.value) return;

  emit('openConversation', card.value);
};

onMounted(() => {
  loadCard();
  loadLabels();
  loadAssignees();
});
</script>

<template>
  <div
    class="mx-auto flex max-h-[92vh] w-full max-w-[calc(100vw-1rem)] flex-col overflow-hidden rounded-xl bg-n-background xl:max-w-[96rem] 2xl:max-w-[118rem]"
  >
    <div
      class="flex items-center justify-between gap-4 border-b border-n-weak px-2 py-4"
    >
      <div class="min-w-0">
        <h2 class="mb-0 truncate text-base font-semibold text-n-slate-12">
          {{ modalTitle }}
        </h2>
      </div>
      <div v-if="cardDisplayId" class="flex flex-shrink-0 items-center gap-2">
        <span
          data-testid="kanban-opportunity-card-id"
          class="text-sm font-medium text-n-slate-11"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID', { id: cardDisplayId }) }}
        </span>
        <button
          type="button"
          data-testid="kanban-opportunity-copy-card-id"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID')"
          @click="copyCardId"
        >
          <i class="i-lucide-copy size-4" />
        </button>
      </div>
    </div>

    <div class="overflow-auto px-2 py-4">
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

      <form
        v-else-if="card"
        data-testid="kanban-opportunity-form"
        class="grid gap-5"
        @submit.prevent="saveCard"
      >
        <div
          data-testid="kanban-opportunity-layout"
          class="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(16rem,18rem)]"
        >
          <section class="grid min-w-0 content-start gap-4">
            <NextInput
              v-model="subject"
              data-testid="kanban-opportunity-subject"
              class="w-full"
              :label="t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE')"
              :message="subjectError"
              :message-type="subjectError ? 'error' : 'info'"
              autofocus
              @input="subjectError = ''"
            />

            <section class="grid gap-2 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.CONTACT') }}
              </h3>
              <p
                data-testid="kanban-opportunity-contact"
                class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
              >
                <i class="i-lucide-user-round size-4 flex-shrink-0" />
                <span class="min-w-0 truncate">{{ contactName }}</span>
              </p>
            </section>

            <label class="grid gap-1.5">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION') }}
              </span>
              <textarea
                v-model="description"
                rows="12"
                data-testid="kanban-opportunity-description"
                class="min-h-[18rem] max-w-full w-full min-w-0 resize-y rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                :placeholder="
                  t('KANBAN.OPPORTUNITY_DETAILS.DESCRIPTION_PLACEHOLDER')
                "
              />
            </label>
          </section>

          <aside class="grid min-w-0 content-start gap-4">
            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.CONVERSATION') }}
              </h3>
              <p
                v-if="hasConversation"
                data-testid="kanban-opportunity-conversation"
                class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
              >
                <i class="i-lucide-inbox size-4 flex-shrink-0" />
                <span class="min-w-0 truncate">{{ inboxName }}</span>
              </p>
              <p
                v-else
                data-testid="kanban-opportunity-no-conversation"
                class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
              >
                <i class="i-lucide-message-square-off size-4" />
                {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION') }}
              </p>
              <NextButton
                v-if="hasConversation"
                type="button"
                outline
                slate
                xs
                data-testid="kanban-opportunity-open-conversation"
                icon="i-lucide-external-link"
                :label="t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION')"
                @click="openConversation"
              />
            </section>

            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.LABELS') }}
              </h3>
              <p
                v-if="labelsLoadError"
                data-testid="kanban-opportunity-labels-load-error"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ labelsLoadError }}
              </p>

              <Popover
                align="start"
                disable-mobile-view
                :show-content-border="false"
              >
                <button
                  type="button"
                  data-testid="kanban-opportunity-labels-menu"
                  class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isLoadingLabels || isSavingLabels"
                >
                  <i
                    class="i-lucide-tags size-4 flex-shrink-0 text-n-slate-11"
                  />
                  <span class="min-w-0 flex-1 truncate">
                    {{ selectedLabelsSummary }}
                  </span>
                  <i
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
                      allow-creation
                      @add="onAddLabel"
                      @remove="onRemoveLabel"
                    />
                  </div>
                </template>
              </Popover>

              <div
                v-if="selectedLabels.length"
                data-testid="kanban-opportunity-labels"
                class="flex flex-wrap gap-2"
              >
                <span
                  v-for="label in selectedLabels"
                  :key="label.id || label.title"
                  data-testid="kanban-opportunity-label"
                  class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
                >
                  <span
                    class="size-2 rounded-full"
                    :style="{ backgroundColor: label.color }"
                  />
                  <span>{{ label.title }}</span>
                </span>
              </div>

              <p
                v-else-if="!isLoadingLabels && !labelsLoadError"
                data-testid="kanban-opportunity-no-labels"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED') }}
              </p>

              <p
                v-if="labelsSaveError"
                data-testid="kanban-opportunity-labels-save-error"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ labelsSaveError }}
              </p>
            </section>

            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE') }}
              </h3>
              <p
                v-if="assigneesLoadError"
                data-testid="kanban-opportunity-assignees-load-error"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ assigneesLoadError }}
              </p>

              <Popover
                align="start"
                disable-mobile-view
                :show-content-border="false"
              >
                <button
                  type="button"
                  data-testid="kanban-opportunity-assignees-menu"
                  class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isLoadingAssignees || isSavingAssignees"
                >
                  <i
                    class="i-lucide-users size-4 flex-shrink-0 text-n-slate-11"
                  />
                  <span class="min-w-0 flex-1 truncate">
                    {{ assigneesSummary }}
                  </span>
                  <i
                    class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
                  />
                </button>

                <template #content>
                  <div
                    class="block visible w-72 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
                  >
                    <ul class="grid gap-1">
                      <li v-for="user in assignableUsers" :key="user.id">
                        <button
                          type="button"
                          data-testid="kanban-opportunity-assignee-option"
                          :data-selected="selectedAssigneeIds.includes(user.id)"
                          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                          @click="onToggleAssignee(user)"
                        >
                          <input
                            type="checkbox"
                            class="pointer-events-none"
                            :checked="selectedAssigneeIds.includes(user.id)"
                            tabindex="-1"
                          />
                          <Avatar
                            :name="user.name"
                            :src="user.avatar_url"
                            :size="20"
                            rounded-full
                          />
                          <span class="min-w-0 flex-1 truncate">
                            {{ user.name }}
                          </span>
                        </button>
                      </li>
                    </ul>
                    <p
                      v-if="!assignableUsers.length"
                      class="mb-0 px-2 py-1.5 text-sm text-n-slate-11"
                    >
                      {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_ASSIGNABLE_USERS') }}
                    </p>
                  </div>
                </template>
              </Popover>

              <div
                v-if="assignedUsers.length"
                data-testid="kanban-opportunity-assignees"
                class="flex flex-wrap gap-2"
              >
                <span
                  v-for="user in assignedUsers"
                  :key="user.id"
                  data-testid="kanban-opportunity-assignee"
                  class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
                >
                  <Avatar
                    :name="user.name"
                    :src="user.avatar_url"
                    :size="16"
                    rounded-full
                  />
                  <span>{{ user.name }}</span>
                </span>
              </div>
              <p
                v-else-if="!isLoadingAssignees && !assigneesLoadError"
                data-testid="kanban-opportunity-no-assignees"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{ t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED') }}
              </p>

              <p
                v-if="assigneesSaveError"
                data-testid="kanban-opportunity-assignees-save-error"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ assigneesSaveError }}
              </p>
            </section>

            <section class="grid gap-2 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY') }}
              </h3>
              <select
                v-model="priority"
                data-testid="kanban-opportunity-priority"
                class="min-h-10 w-full rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
              >
                <option
                  v-for="option in priorityOptions"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </section>

            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.DATES') }}
              </h3>
              <KanbanDueDatePicker
                v-model="dueAt"
                data-testid="kanban-opportunity-due-at"
                :label="t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE')"
                :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
                :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
              />
            </section>
          </aside>
        </div>

        <p
          v-if="saveError"
          data-testid="kanban-opportunity-save-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ saveError }}
        </p>

        <div
          class="flex items-center justify-end gap-3 border-t border-n-weak pt-4"
        >
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
            type="submit"
            sm
            data-testid="kanban-opportunity-save"
            :label="
              isSaving
                ? t('KANBAN.OPPORTUNITY_DETAILS.SAVING')
                : t('KANBAN.OPPORTUNITY_DETAILS.SAVE')
            "
            :disabled="isSaving"
            :is-loading="isSaving"
          />
        </div>
      </form>
    </div>
  </div>
</template>
