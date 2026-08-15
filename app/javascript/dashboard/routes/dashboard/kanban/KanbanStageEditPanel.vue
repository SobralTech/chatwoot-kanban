<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

defineProps({
  panelClass: {
    type: String,
    default: 'border-n-weak bg-n-surface-1',
  },
  showColorPicker: {
    type: Boolean,
    default: false,
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['save', 'cancel']);

const name = defineModel('name', { type: String, default: '' });
const description = defineModel('description', { type: String, default: '' });
const color = defineModel('color', { type: String, default: '' });

const { t } = useI18n();
</script>

<template>
  <div
    data-testid="kanban-board-form-edit-stage-panel"
    class="grid gap-3 rounded-md border p-3"
    :class="panelClass"
  >
    <div class="flex min-w-0 items-center gap-3">
      <ColorPicker
        v-if="showColorPicker"
        v-model="color"
        data-testid="kanban-board-form-edit-stage-color"
        class="flex-none"
      />
      <input
        v-model="name"
        data-testid="kanban-board-form-edit-stage-name"
        type="text"
        class="reset-base !mb-0 h-10 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
        :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
      />
    </div>
    <textarea
      v-model="description"
      data-testid="kanban-board-form-edit-stage-description"
      rows="2"
      class="!mb-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
      :placeholder="
        t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_DESCRIPTION_PLACEHOLDER')
      "
    />
    <div class="flex flex-wrap items-center gap-2">
      <Button
        type="button"
        data-testid="kanban-board-form-save-stage"
        icon="i-lucide-check"
        :label="t('KANBAN.ACTIONS.SAVE_STAGE')"
        color="blue"
        size="sm"
        :disabled="!name.trim()"
        :is-loading="isUpdating"
        @click="$emit('save')"
      />
      <Button
        type="button"
        icon="i-lucide-x"
        :label="t('KANBAN.ACTIONS.CANCEL')"
        color="slate"
        size="sm"
        @click="$emit('cancel')"
      />
    </div>
  </div>
</template>
