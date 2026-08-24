<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanReasonPicker from './KanbanReasonPicker.vue';

const props = defineProps({
  reasonType: {
    type: String,
    required: true,
    validator: value => ['won', 'lost', 'reopen'].includes(value),
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  required: {
    type: Boolean,
    default: false,
  },
  showBack: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['back', 'confirm']);

const { t } = useI18n();

const selectedReasonId = ref('');

const isReopenConfirmation = computed(() => props.reasonType === 'reopen');

const canConfirm = computed(
  () =>
    isReopenConfirmation.value || !props.required || !!selectedReasonId.value
);

const onConfirm = () => {
  if (!canConfirm.value) return;

  emit('confirm', selectedReasonId.value || null);
};
</script>

<template>
  <div class="grid gap-2">
    <p v-if="isReopenConfirmation" class="mb-0 text-sm text-n-slate-12">
      {{ t('KANBAN.CARD.STATUS.REOPEN_CONFIRMATION') }}
    </p>

    <KanbanReasonPicker
      v-else
      v-model="selectedReasonId"
      :reasons="reasons"
      :reason-type="reasonType"
      :required="required"
      testid="kanban-card-status-reason-select"
    />

    <div class="flex items-center justify-between gap-2 pt-1">
      <button
        v-if="showBack"
        type="button"
        data-testid="kanban-card-status-back"
        class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
        @click="emit('back')"
      >
        {{ t('KANBAN.CARD.STATUS.BACK') }}
      </button>
      <span v-else />
      <button
        type="button"
        data-testid="kanban-card-status-confirm"
        class="rounded-md bg-n-brand px-3 py-1.5 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canConfirm"
        @click="onConfirm"
      >
        {{ t('KANBAN.CARD.STATUS.CONFIRM') }}
      </button>
    </div>
  </div>
</template>
