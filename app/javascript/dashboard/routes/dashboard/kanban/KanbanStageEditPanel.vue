<script setup>
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';

// The create-stage and edit-stage forms are the same fields; only their labels
// and test ids differ, so they stay one component rather than two layouts that
// have to be restyled in step.
const props = defineProps({
  panelClass: {
    type: String,
    default: 'border-n-weak bg-n-surface-1',
  },
  testidPrefix: {
    type: String,
    default: 'kanban-board-form-edit-stage',
  },
  saveTestid: {
    type: String,
    default: 'kanban-board-form-save-stage',
  },
  saveLabelKey: {
    type: String,
    default: 'KANBAN.ACTIONS.SAVE_STAGE',
  },
  showColorPicker: {
    type: Boolean,
    default: false,
  },
  showSlaHours: {
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
const slaHours = defineModel('slaHours', {
  type: [Number, String],
  default: null,
});

const { t } = useI18n();

const testid = suffix => `${props.testidPrefix}-${suffix}`;
</script>

<template>
  <div
    :data-testid="testid('panel')"
    class="grid gap-3 rounded-md border p-3"
    :class="panelClass"
  >
    <div class="flex w-full min-w-0 flex-wrap items-end gap-3">
      <ColorPicker
        v-if="showColorPicker"
        v-model="color"
        :data-testid="testid('color')"
        class="flex-none"
      />
      <input
        v-model="name"
        :data-testid="testid('name')"
        type="text"
        class="reset-base !mb-0 h-10 w-0 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
        :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
      />
      <label
        v-if="showSlaHours"
        class="grid w-32 max-w-full min-w-0 flex-none gap-1 text-xs font-medium text-n-slate-11"
      >
        {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.SLA_HOURS') }}
        <input
          v-model="slaHours"
          :data-testid="testid('sla-hours')"
          type="number"
          min="1"
          step="1"
          class="reset-base !mb-0 h-10 w-full min-w-0 rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
          :placeholder="t('KANBAN.BOARD_EDIT.STAGES_TAB.SLA_HOURS_PLACEHOLDER')"
        />
      </label>
    </div>
    <p v-if="showSlaHours" class="text-xs font-normal text-n-slate-10">
      {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.SLA_HOURS_HELP') }}
    </p>
    <textarea
      v-model="description"
      :data-testid="testid('description')"
      rows="2"
      class="!mb-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
      :placeholder="
        t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_DESCRIPTION_PLACEHOLDER')
      "
    />
    <div class="flex flex-wrap items-center gap-2">
      <Button
        type="button"
        :data-testid="saveTestid"
        icon="i-lucide-check"
        :label="t(saveLabelKey)"
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
