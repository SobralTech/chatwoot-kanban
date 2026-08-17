<script setup>
import { ref } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

defineProps({
  newStageName: {
    type: String,
    default: '',
  },
  newStageColor: {
    type: String,
    required: true,
  },
  isCreatingStage: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'update:newStageName',
  'update:newStageColor',
  'createStage',
  'cancelStageDraft',
]);

const nameInput = ref(null);
const { t } = useI18n();

const focus = () => nameInput.value?.focus();
defineExpose({ focus });
</script>

<template>
  <OnClickOutside class="flex-shrink-0" @trigger="emit('cancelStageDraft')">
    <section
      class="flex w-64 lg:w-80 flex-shrink-0 snap-start flex-col gap-3 rounded-lg border border-dashed border-n-weak bg-n-alpha-1 p-3"
      @keydown.escape.prevent="emit('cancelStageDraft')"
    >
      <form class="flex flex-col gap-3" @submit.prevent="emit('createStage')">
        <div class="flex items-center gap-3">
          <ColorPicker
            :model-value="newStageColor"
            :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
            data-testid="kanban-new-stage-color-picker"
            class="flex-shrink-0"
            @update:model-value="emit('update:newStageColor', $event)"
          />
          <input
            ref="nameInput"
            :value="newStageName"
            type="text"
            data-testid="kanban-new-stage-name-input"
            autofocus
            class="reset-base !mb-0 h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
            @input="emit('update:newStageName', $event.target.value)"
          />
        </div>
        <div class="flex justify-end gap-2">
          <NextButton
            type="submit"
            icon="i-lucide-check"
            :label="t('KANBAN.ACTIONS.CREATE_STAGE_CONFIRM')"
            color="blue"
            size="sm"
            :is-loading="isCreatingStage"
            :disabled="isCreatingStage"
            data-testid="kanban-create-stage-confirm"
          />
          <NextButton
            icon="i-lucide-x"
            :label="t('KANBAN.ACTIONS.CANCEL')"
            color="slate"
            variant="ghost"
            size="sm"
            :disabled="isCreatingStage"
            data-testid="kanban-create-stage-cancel"
            @click="emit('cancelStageDraft')"
          />
        </div>
      </form>
    </section>
  </OnClickOutside>
</template>
