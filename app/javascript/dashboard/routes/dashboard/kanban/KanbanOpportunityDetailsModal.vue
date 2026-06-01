<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

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

const card = ref(null);
const subject = ref('');
const startsAt = ref('');
const dueAt = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const loadError = ref('');
const saveError = ref('');
const subjectError = ref('');

const hasConversation = computed(() => !!card.value?.conversationId);

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
  startsAt.value = formatDateTimeInput(card.value.startsAt);
  dueAt.value = formatDateTimeInput(card.value.dueAt);
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

const openConversation = () => {
  if (!hasConversation.value) return;

  emit('openConversation', card.value);
};

onMounted(loadCard);
</script>

<template>
  <div class="flex max-h-[80vh] w-full max-w-xl flex-col overflow-auto">
    <div class="flex items-start justify-between gap-3 px-6 pt-6">
      <woot-modal-header
        class="min-w-0 !px-0 !pt-0"
        :header-title="t('KANBAN.OPPORTUNITY_DETAILS.TITLE')"
      />
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

    <div class="px-6 pb-6">
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
        class="grid gap-4"
        @submit.prevent="saveCard"
      >
        <NextInput
          v-model="subject"
          data-testid="kanban-opportunity-subject"
          :label="t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE')"
          :message="subjectError"
          :message-type="subjectError ? 'error' : 'info'"
          autofocus
          @input="subjectError = ''"
        />

        <div class="grid gap-3 sm:grid-cols-2">
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

        <p
          v-if="saveError"
          data-testid="kanban-opportunity-save-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ saveError }}
        </p>

        <div
          class="flex items-center justify-between gap-3 border-t border-n-weak pt-4"
        >
          <NextButton
            v-if="hasConversation"
            type="button"
            outline
            slate
            sm
            data-testid="kanban-opportunity-open-conversation"
            icon="i-lucide-message-square"
            :label="t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION')"
            @click="openConversation"
          />
          <p
            v-else
            data-testid="kanban-opportunity-no-conversation"
            class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
          >
            <i class="i-lucide-message-square-off size-4" />
            {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION') }}
          </p>

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
