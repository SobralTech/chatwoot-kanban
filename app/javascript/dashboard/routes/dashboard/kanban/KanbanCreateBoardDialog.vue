<script setup>
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
  isCreating: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:modelValue', 'create', 'close']);

const { t } = useI18n();

const boardName = ref('');
const boardNameInput = ref(null);

const closeDialog = () => {
  boardName.value = '';
  emit('update:modelValue', false);
  emit('close');
};

const createBoard = () => {
  const name = boardName.value.trim();
  if (!name || props.isCreating) return;

  emit('create', name);
};

watch(
  () => props.modelValue,
  isOpen => {
    if (isOpen) {
      nextTick(() => boardNameInput.value?.focus());
      return;
    }

    boardName.value = '';
  }
);
</script>

<template>
  <div>
    <div
      v-if="modelValue"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/40 px-4 backdrop-blur-sm"
      data-testid="kanban-create-board-dialog"
      role="dialog"
      aria-modal="true"
      :aria-label="t('KANBAN.OVERVIEW.CREATE_BOARD_MODAL_TITLE')"
      @keydown.escape.prevent="closeDialog"
    >
      <form
        class="w-full max-w-sm rounded-lg border border-n-weak bg-n-surface-1 p-4 shadow-xl"
        @submit.prevent="createBoard"
      >
        <label
          for="kanban-create-board-name"
          class="mb-2 block text-sm font-medium text-n-slate-12"
        >
          {{ t('KANBAN.OVERVIEW.CREATE_BOARD_MODAL_TITLE') }}
        </label>
        <input
          id="kanban-create-board-name"
          ref="boardNameInput"
          v-model="boardName"
          type="text"
          class="w-full rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
          :placeholder="t('KANBAN.ACTIONS.BOARD_NAME_PLACEHOLDER')"
          data-testid="kanban-create-board-name-input"
          @keydown.enter.prevent="createBoard"
        />
        <p
          v-if="error"
          class="mt-2 text-sm text-n-ruby-11"
          data-testid="kanban-create-board-error"
        >
          {{ error }}
        </p>
        <div class="mt-4 flex justify-end gap-2">
          <button
            type="submit"
            class="flex size-9 items-center justify-center rounded-md border border-n-weak bg-n-surface-2 text-n-slate-12 transition-colors hover:bg-n-teal-9 hover:text-white focus:outline-none focus:ring-2 focus:ring-n-teal-8 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-n-surface-2 disabled:hover:text-n-slate-12"
            :disabled="!boardName.trim() || isCreating"
            :aria-label="t('KANBAN.ACTIONS.CONFIRM_CREATE_BOARD')"
            :title="t('KANBAN.ACTIONS.CONFIRM_CREATE_BOARD')"
            data-testid="kanban-create-board-confirm"
          >
            <i class="i-lucide-check size-4" />
          </button>
          <button
            type="button"
            class="flex size-9 items-center justify-center rounded-md border border-n-weak bg-n-surface-2 text-n-slate-12 transition-colors hover:bg-n-ruby-9 hover:text-white focus:outline-none focus:ring-2 focus:ring-n-ruby-8"
            :aria-label="t('KANBAN.ACTIONS.CANCEL_CREATE_BOARD')"
            :title="t('KANBAN.ACTIONS.CANCEL_CREATE_BOARD')"
            data-testid="kanban-create-board-cancel"
            @click="closeDialog"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
