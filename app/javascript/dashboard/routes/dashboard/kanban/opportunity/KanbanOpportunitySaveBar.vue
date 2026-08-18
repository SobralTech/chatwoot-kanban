<script setup>
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  isSaving: {
    type: Boolean,
    default: false,
  },
  hasUnsavedChanges: {
    type: Boolean,
    default: false,
  },
  savedAt: {
    type: Number,
    default: null,
  },
  savedTimeLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['save', 'close']);

const { t } = useI18n();
</script>

<template>
  <div
    data-testid="kanban-opportunity-savebar"
    class="flex flex-none items-center justify-between gap-3 border-t border-n-weak bg-n-background px-4 py-3"
  >
    <p
      data-testid="kanban-opportunity-save-state"
      class="mb-0 text-sm text-n-slate-11"
    >
      <span v-if="isSaving">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.SAVING_STATE') }}
      </span>
      <span v-else-if="hasUnsavedChanges">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_STATE') }}
      </span>
      <span v-else-if="savedAt">
        {{
          t('KANBAN.OPPORTUNITY_DETAILS.SAVED_AGO', { time: savedTimeLabel })
        }}
      </span>
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
        @click="emit('save')"
      />
    </div>
  </div>
</template>
