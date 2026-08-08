<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();

const isLoading = ref(false);
const loadError = ref('');
const reasons = ref([]);
const showFormModal = ref(false);
const editingReasonId = ref(null);
const isSaving = ref(false);
const formError = ref('');
const showRemoveConfirmation = ref(false);
const reasonPendingRemoval = ref(null);
const isRemoving = ref(false);

const form = reactive({
  title: '',
  description: '',
  reasonType: 'lost',
});

const lostReasons = computed(() =>
  reasons.value
    .filter(reason => reason.reasonType === 'lost')
    .sort((a, b) => a.position - b.position)
);

const wonReasons = computed(() =>
  reasons.value
    .filter(reason => reason.reasonType === 'won')
    .sort((a, b) => a.position - b.position)
);

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallback;

const fetchReasons = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getReasons(props.boardId);
    reasons.value = camelcaseKeys(response.data || [], { deep: true });
  } catch (error) {
    loadError.value = getErrorMessage(error, t('KANBAN.REASONS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const resetForm = () => {
  form.title = '';
  form.description = '';
  form.reasonType = 'lost';
  formError.value = '';
};

const openAddReasonModal = (reasonType = 'lost') => {
  resetForm();
  form.reasonType = reasonType;
  editingReasonId.value = null;
  showFormModal.value = true;
};

const openEditReasonModal = reason => {
  editingReasonId.value = reason.id;
  form.title = reason.title;
  form.description = reason.description || '';
  form.reasonType = reason.reasonType;
  formError.value = '';
  showFormModal.value = true;
};

const closeFormModal = () => {
  showFormModal.value = false;
  editingReasonId.value = null;
  resetForm();
};

const saveReason = async () => {
  const title = form.title.trim();
  if (isSaving.value) return;

  if (!title) {
    formError.value = t('KANBAN.REASONS.FORM.REQUIRED_TITLE');
    return;
  }

  isSaving.value = true;
  formError.value = '';

  const payload = {
    reason: {
      title,
      description: form.description.trim(),
      reason_type: form.reasonType,
    },
  };

  try {
    if (editingReasonId.value) {
      await KanbanBoardsAPI.updateReason(
        props.boardId,
        editingReasonId.value,
        payload
      );
      useAlert(t('KANBAN.REASONS.UPDATE_SUCCESS'));
    } else {
      await KanbanBoardsAPI.createReason(props.boardId, payload);
      useAlert(t('KANBAN.REASONS.CREATE_SUCCESS'));
    }
    closeFormModal();
    await fetchReasons();
  } catch (error) {
    const fallback = editingReasonId.value
      ? t('KANBAN.REASONS.UPDATE_ERROR')
      : t('KANBAN.REASONS.CREATE_ERROR');
    formError.value = getErrorMessage(error, fallback);
    useAlert(formError.value);
  } finally {
    isSaving.value = false;
  }
};

const openRemoveConfirmation = reason => {
  reasonPendingRemoval.value = reason;
  showRemoveConfirmation.value = true;
};

const closeRemoveConfirmation = () => {
  showRemoveConfirmation.value = false;
  reasonPendingRemoval.value = null;
};

const removeReason = async () => {
  const reason = reasonPendingRemoval.value;
  if (!reason || isRemoving.value) return;

  isRemoving.value = true;

  try {
    await KanbanBoardsAPI.deleteReason(props.boardId, reason.id);
    closeRemoveConfirmation();
    await fetchReasons();
    useAlert(t('KANBAN.REASONS.REMOVE_SUCCESS'));
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.REASONS.REMOVE_ERROR')));
  } finally {
    isRemoving.value = false;
  }
};

onMounted(fetchReasons);
</script>

<template>
  <div class="grid gap-4" data-testid="kanban-reasons-tab">
    <div class="flex items-center justify-end">
      <Button
        icon="i-lucide-plus"
        :label="t('KANBAN.REASONS.ADD_REASON')"
        color="slate"
        size="sm"
        data-testid="kanban-reasons-add"
        @click="openAddReasonModal('lost')"
      />
    </div>

    <p
      v-if="isLoading"
      data-testid="kanban-reasons-loading"
      class="text-sm text-n-slate-11"
    >
      {{ t('KANBAN.REASONS.LOADING') }}
    </p>

    <p
      v-else-if="loadError"
      data-testid="kanban-reasons-load-error"
      class="text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>

    <div v-else class="grid gap-4 sm:grid-cols-2">
      <section
        class="grid content-start gap-3 rounded-lg border border-n-weak p-4"
      >
        <header class="flex items-center gap-2">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.REASONS.LOST_COLUMN_TITLE') }}
          </h3>
          <span
            class="flex-none rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ lostReasons.length }}
          </span>
        </header>

        <p
          v-if="!lostReasons.length"
          data-testid="kanban-reasons-empty-lost"
          class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.REASONS.EMPTY_LOST') }}
        </p>

        <div v-else class="grid gap-2">
          <div
            v-for="reason in lostReasons"
            :key="reason.id"
            data-testid="kanban-reason-row"
            class="flex items-start gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2"
          >
            <div class="min-w-0 flex-1">
              <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                {{ reason.title }}
              </p>
              <p
                v-if="reason.description"
                class="mb-0 line-clamp-2 text-xs text-n-slate-11"
              >
                {{ reason.description }}
              </p>
            </div>
            <div class="flex flex-none items-center gap-1">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                :title="t('KANBAN.REASONS.EDIT_REASON')"
                data-testid="kanban-reason-edit"
                @click="openEditReasonModal(reason)"
              />
              <Button
                icon="i-lucide-trash"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('KANBAN.REASONS.REMOVE_REASON')"
                data-testid="kanban-reason-remove"
                @click="openRemoveConfirmation(reason)"
              />
            </div>
          </div>
        </div>
      </section>

      <section
        class="grid content-start gap-3 rounded-lg border border-n-weak p-4"
      >
        <header class="flex items-center gap-2">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.REASONS.WON_COLUMN_TITLE') }}
          </h3>
          <span
            class="flex-none rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ wonReasons.length }}
          </span>
        </header>

        <p
          v-if="!wonReasons.length"
          data-testid="kanban-reasons-empty-won"
          class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.REASONS.EMPTY_WON') }}
        </p>

        <div v-else class="grid gap-2">
          <div
            v-for="reason in wonReasons"
            :key="reason.id"
            data-testid="kanban-reason-row"
            class="flex items-start gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2"
          >
            <div class="min-w-0 flex-1">
              <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                {{ reason.title }}
              </p>
              <p
                v-if="reason.description"
                class="mb-0 line-clamp-2 text-xs text-n-slate-11"
              >
                {{ reason.description }}
              </p>
            </div>
            <div class="flex flex-none items-center gap-1">
              <Button
                icon="i-lucide-pencil"
                variant="ghost"
                color="slate"
                size="sm"
                :title="t('KANBAN.REASONS.EDIT_REASON')"
                data-testid="kanban-reason-edit"
                @click="openEditReasonModal(reason)"
              />
              <Button
                icon="i-lucide-trash"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('KANBAN.REASONS.REMOVE_REASON')"
                data-testid="kanban-reason-remove"
                @click="openRemoveConfirmation(reason)"
              />
            </div>
          </div>
        </div>
      </section>
    </div>

    <woot-modal
      v-model:show="showFormModal"
      :on-close="closeFormModal"
      :show-close-button="false"
    >
      <div
        class="flex w-full flex-col gap-4 rounded-lg bg-n-surface-1 p-6 text-n-slate-12"
        data-testid="kanban-reason-form-modal"
      >
        <h3 class="mb-0 text-lg font-medium">
          {{
            editingReasonId
              ? t('KANBAN.REASONS.FORM.EDIT_TITLE')
              : t('KANBAN.REASONS.FORM.ADD_TITLE')
          }}
        </h3>

        <form
          class="grid w-full gap-5 !self-stretch !p-0"
          @submit.prevent="saveReason"
        >
          <div class="grid gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.REASONS.FORM.TYPE_LABEL') }}
            </span>
            <div class="grid grid-cols-2 gap-3">
              <button
                type="button"
                data-testid="kanban-reason-type-lost"
                class="flex flex-col items-center gap-2 rounded-lg border-2 px-4 py-5 text-sm font-medium transition-colors"
                :class="
                  form.reasonType === 'lost'
                    ? 'border-n-ruby-9 bg-n-ruby-3 text-n-ruby-11'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
                "
                @click="form.reasonType = 'lost'"
              >
                <i class="i-lucide-x-circle size-6" />
                {{ t('KANBAN.REASONS.FORM.TYPE_LOST') }}
              </button>
              <button
                type="button"
                data-testid="kanban-reason-type-won"
                class="flex flex-col items-center gap-2 rounded-lg border-2 px-4 py-5 text-sm font-medium transition-colors"
                :class="
                  form.reasonType === 'won'
                    ? 'border-n-teal-9 bg-n-teal-3 text-n-teal-11'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
                "
                @click="form.reasonType = 'won'"
              >
                <i class="i-lucide-check-circle-2 size-6" />
                {{ t('KANBAN.REASONS.FORM.TYPE_WON') }}
              </button>
            </div>
          </div>

          <NextInput
            v-model="form.title"
            data-testid="kanban-reason-title"
            :label="t('KANBAN.REASONS.FORM.FIELD_TITLE')"
            :placeholder="t('KANBAN.REASONS.FORM.TITLE_PLACEHOLDER')"
            :message="formError"
            :message-type="formError ? 'error' : 'info'"
            autofocus
            @input="formError = ''"
          />

          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.REASONS.FORM.FIELD_DESCRIPTION') }}
            <textarea
              v-model="form.description"
              data-testid="kanban-reason-description"
              rows="3"
              :placeholder="t('KANBAN.REASONS.FORM.DESCRIPTION_PLACEHOLDER')"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            />
          </label>

          <div class="flex justify-end gap-2">
            <Button
              type="button"
              :label="t('KANBAN.REASONS.FORM.CANCEL')"
              color="slate"
              size="sm"
              data-testid="kanban-reason-cancel"
              @click="closeFormModal"
            />
            <Button
              type="submit"
              :label="t('KANBAN.REASONS.FORM.SAVE')"
              color="blue"
              size="sm"
              :disabled="!form.title.trim()"
              :is-loading="isSaving"
              data-testid="kanban-reason-save"
            />
          </div>
        </form>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showRemoveConfirmation"
      :on-close="closeRemoveConfirmation"
      :on-confirm="removeReason"
      :is-loading="isRemoving"
      :title="t('KANBAN.REASONS.REMOVE_CONFIRM.TITLE')"
      :message="t('KANBAN.REASONS.REMOVE_CONFIRM.MESSAGE')"
      :confirm-text="t('KANBAN.REASONS.REMOVE_CONFIRM.CONFIRM')"
      :reject-text="t('KANBAN.REASONS.REMOVE_CONFIRM.CANCEL')"
    />
  </div>
</template>
