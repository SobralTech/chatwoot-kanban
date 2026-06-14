<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  boardName: {
    type: String,
    default: '',
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
const startsAt = ref('');
const dueAt = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingLabels = ref(false);
const isSavingLabels = ref(false);
const loadError = ref('');
const saveError = ref('');
const labelsLoadError = ref('');
const labelsSaveError = ref('');
const subjectError = ref('');
const selectedLabelTitles = ref([]);

const modalTitle = computed(() =>
  props.boardName
    ? t('KANBAN.OPPORTUNITY_DETAILS.TITLE_WITH_BOARD', {
        boardName: props.boardName,
      })
    : t('KANBAN.OPPORTUNITY_DETAILS.TITLE')
);
const cardDisplayId = computed(() => card.value?.id || props.cardId);
const hasConversation = computed(() => !!card.value?.conversationId);
const conversationDisplayId = computed(
  () => card.value?.conversationId || card.value?.conversation?.id
);
const conversationAssignee = computed(
  () => card.value?.conversation?.meta?.assignee || card.value?.assignee
);
const assigneeName = computed(
  () =>
    conversationAssignee.value?.name ||
    t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED')
);
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

const normalizeCard = payload => ({
  ...payload,
  accountId: payload.accountId ?? payload.account_id,
  kanbanBoardId: payload.kanbanBoardId ?? payload.kanban_board_id,
  kanbanStageId: payload.kanbanStageId ?? payload.kanban_stage_id,
  conversationId: payload.conversationId ?? payload.conversation_id,
  startsAt: payload.startsAt ?? payload.starts_at,
  dueAt: payload.dueAt ?? payload.due_at,
});

const formatDateTimeInput = value => {
  if (!value) return '';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value).slice(0, 16);

  const offset = date.getTimezoneOffset();
  const localDate = new Date(date.getTime() - offset * 60000);
  return localDate.toISOString().slice(0, 16);
};

const toIso8601 = value => (value ? new Date(value).toISOString() : null);

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
  startsAt.value = formatDateTimeInput(card.value.startsAt);
  dueAt.value = formatDateTimeInput(card.value.dueAt);
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
      starts_at: toIso8601(startsAt.value),
      due_at: toIso8601(dueAt.value),
    };
    const response = await KanbanBoardsAPI.updateCardDetailsById(
      props.boardId,
      props.cardId,
      payload
    );
    const updatedCard = normalizeCard(response.data || {});
    setFormState(updatedCard);
    emit('updated', updatedCard);
  } catch (error) {
    saveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const toggleLabel = title => {
  labelsSaveError.value = '';

  selectedLabelTitles.value = selectedLabelTitleSet.value.has(title)
    ? selectedLabelTitles.value.filter(selectedTitle => selectedTitle !== title)
    : [...selectedLabelTitles.value, title];
};

const saveLabels = async () => {
  if (isSavingLabels.value) return;

  isSavingLabels.value = true;
  labelsSaveError.value = '';

  try {
    const response = await KanbanBoardsAPI.updateCardLabels(
      props.boardId,
      props.cardId,
      selectedLabelTitles.value
    );
    selectedLabelTitles.value = getLabelsPayload(response).map(
      label => label.title || label
    );
  } catch (error) {
    labelsSaveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_LABELS_ERROR')
    );
  } finally {
    isSavingLabels.value = false;
  }
};

const openConversation = () => {
  if (!hasConversation.value) return;

  emit('openConversation', card.value);
};

onMounted(() => {
  loadCard();
  loadLabels();
});
</script>

<template>
  <div
    class="mx-auto flex max-h-[92vh] w-full max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-xl bg-n-background 2xl:max-w-[96rem]"
  >
    <div
      class="flex items-start justify-between gap-4 border-b border-n-weak px-5 py-4"
    >
      <div class="min-w-0">
        <h2 class="mb-1 truncate text-base font-semibold text-n-slate-12">
          {{ modalTitle }}
        </h2>
        <p
          v-if="cardDisplayId"
          data-testid="kanban-opportunity-card-id"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID', { id: cardDisplayId }) }}
        </p>
      </div>
      <button
        type="button"
        data-testid="kanban-opportunity-close"
        class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE')"
        @click="emit('close')"
      >
        <i class="i-lucide-x size-4" />
      </button>
    </div>

    <div class="overflow-auto px-5 py-4">
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
          class="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,4fr)_minmax(16rem,1fr)]"
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
            <section class="grid gap-2 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE') }}
              </h3>
              <p
                data-testid="kanban-opportunity-assignee"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{ assigneeName }}
              </p>
            </section>

            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <div class="flex items-center justify-between gap-3">
                <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.OPPORTUNITY_DETAILS.LABELS') }}
                </h3>
                <button
                  type="button"
                  data-testid="kanban-opportunity-save-labels"
                  class="flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
                  :aria-label="
                    isSavingLabels
                      ? t('KANBAN.OPPORTUNITY_DETAILS.SAVING_LABELS')
                      : t('KANBAN.OPPORTUNITY_DETAILS.SAVE_LABELS')
                  "
                  :disabled="isSavingLabels"
                  @click="saveLabels"
                >
                  <i class="i-lucide-save size-4" />
                </button>
              </div>

              <p
                v-if="labelsLoadError"
                data-testid="kanban-opportunity-labels-load-error"
                class="mb-0 text-sm text-n-ruby-11"
              >
                {{ labelsLoadError }}
              </p>

              <div
                v-if="accountLabels.length"
                data-testid="kanban-opportunity-labels"
                class="flex flex-wrap gap-2"
              >
                <button
                  v-for="label in accountLabels"
                  :key="label.id || label.title"
                  type="button"
                  data-testid="kanban-opportunity-label"
                  class="flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-medium transition"
                  :class="
                    selectedLabelTitleSet.has(label.title)
                      ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-12'
                      : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
                  "
                  :aria-pressed="selectedLabelTitleSet.has(label.title)"
                  @click="toggleLabel(label.title)"
                >
                  <span
                    class="size-2 rounded-full"
                    :style="{ backgroundColor: label.color }"
                  />
                  <span>{{ label.title }}</span>
                  <i
                    v-if="selectedLabelTitleSet.has(label.title)"
                    class="i-lucide-check size-3"
                  />
                </button>
              </div>

              <p
                v-else-if="!isLoadingLabels"
                data-testid="kanban-opportunity-no-labels"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_AVAILABLE') }}
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
                {{ t('KANBAN.OPPORTUNITY_DETAILS.CONVERSATION') }}
              </h3>
              <p
                v-if="hasConversation"
                data-testid="kanban-opportunity-conversation"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.CONVERSATION_ID', {
                    id: conversationDisplayId,
                  })
                }}
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
                icon="i-lucide-message-square"
                :label="t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION')"
                @click="openConversation"
              />
            </section>

            <section class="grid gap-2 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.CONTACT') }}
              </h3>
              <p
                data-testid="kanban-opportunity-contact"
                class="mb-0 text-sm text-n-slate-11"
              >
                {{ contactName }}
              </p>
            </section>

            <section class="grid gap-3 rounded-lg border border-n-weak p-3">
              <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.DATES') }}
              </h3>
              <div class="grid gap-3">
                <NextInput
                  v-model="startsAt"
                  type="datetime-local"
                  data-testid="kanban-opportunity-starts-at"
                  :label="t('KANBAN.OPPORTUNITY_DETAILS.START_DATE')"
                />
                <NextInput
                  v-model="dueAt"
                  type="datetime-local"
                  data-testid="kanban-opportunity-due-at"
                  :label="t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE')"
                />
              </div>
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
            icon="i-lucide-save"
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
