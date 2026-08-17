<script setup>
import { computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import KanbanStageMenu from '../KanbanStageMenu.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  stages: {
    type: Array,
    default: () => [],
  },
  boards: {
    type: Array,
    default: () => [],
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
  editingStageId: {
    type: [Number, String],
    default: null,
  },
  stageNames: {
    type: Object,
    default: () => ({}),
  },
  stageColors: {
    type: Object,
    default: () => ({}),
  },
  setStageNameInput: {
    type: Function,
    required: true,
  },
  isTerminalStage: {
    type: Function,
    required: true,
  },
  stageAccent: {
    type: Function,
    required: true,
  },
});

const emit = defineEmits([
  'updateStageName',
  'updateStageColor',
  'updateStage',
  'cancelEditingStage',
  'addCard',
  'editStage',
  'copyStage',
  'moveStage',
  'moveAllCards',
  'sortCards',
  'deleteStage',
  'deleteAllCards',
]);

const { t } = useI18n();

const stageName = computed({
  get: () => props.stageNames[props.stage.id] || '',
  set: value => emit('updateStageName', { stageId: props.stage.id, value }),
});

const stageColor = computed({
  get: () => props.stageColors[props.stage.id] || '',
  set: value => emit('updateStageColor', { stageId: props.stage.id, value }),
});
</script>

<template>
  <header
    class="flex min-h-10 items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
    :class="[
      editingStageId === stage.id ? '' : 'stage-drag-handle cursor-grab',
      stageAccent(stage)?.header,
    ]"
  >
    <OnClickOutside
      v-if="editingStageId === stage.id"
      class="min-w-0 flex-1"
      @trigger="emit('cancelEditingStage')"
    >
      <form
        class="flex min-w-0 w-full items-center gap-2"
        @submit.prevent="emit('updateStage', stage)"
      >
        <ColorPicker
          v-if="!isTerminalStage(stage)"
          v-model="stageColor"
          preview-only
          :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
          data-testid="kanban-stage-color-picker"
          class="flex-shrink-0"
        />
        <input
          :ref="element => setStageNameInput(stage.id, element)"
          v-model="stageName"
          type="text"
          class="reset-base !mb-0 h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
          :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
          @keydown.escape.prevent="emit('cancelEditingStage')"
        />
        <NextButton
          type="submit"
          icon="i-lucide-check"
          ghost
          xs
          slate
          class="no-drag"
          :aria-label="t('KANBAN.ACTIONS.SAVE_STAGE')"
          :title="t('KANBAN.ACTIONS.SAVE_STAGE')"
        />
        <NextButton
          icon="i-lucide-x"
          ghost
          xs
          slate
          class="no-drag"
          :aria-label="t('KANBAN.ACTIONS.CANCEL')"
          :title="t('KANBAN.ACTIONS.CANCEL')"
          @click="emit('cancelEditingStage')"
        />
      </form>
    </OnClickOutside>
    <template v-else>
      <div class="flex min-w-0 flex-1 items-center gap-2">
        <span
          class="size-2.5 flex-shrink-0 rounded-full"
          :class="stageAccent(stage)?.dot"
          :style="
            isTerminalStage(stage) ? null : { backgroundColor: stage.color }
          "
          aria-hidden="true"
        />
        <h3
          class="truncate text-sm font-semibold"
          :class="stageAccent(stage)?.title ?? 'text-n-slate-12'"
        >
          {{ stage.name }}
        </h3>
        <span
          class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
        >
          {{ stage.cardsCount }}
        </span>
        <span
          v-if="stage.totalValue > 0"
          data-testid="kanban-stage-total-value"
          class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
        >
          {{ formatCurrency(stage.totalValue) }}
        </span>
      </div>
      <div class="flex flex-shrink-0 gap-1">
        <KanbanStageMenu
          :stage="stage"
          :stages="stages"
          :boards="boards"
          :won-stage-id="board?.wonStageId"
          :lost-stage-id="board?.lostStageId"
          :is-admin="isAdmin"
          :is-busy="isBusy"
          @add-card="emit('addCard', stage)"
          @edit="emit('editStage', stage)"
          @copy="emit('copyStage', stage, $event)"
          @move="emit('moveStage', stage, $event)"
          @move-cards="emit('moveAllCards', stage, $event)"
          @sort="emit('sortCards', stage, $event)"
          @delete-stage="emit('deleteStage', stage)"
          @delete-cards="emit('deleteAllCards', stage)"
        />
      </div>
    </template>
  </header>
</template>
