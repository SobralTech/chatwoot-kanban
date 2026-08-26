<script setup>
import { computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';
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
  suppressNextClick: {
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
  terminalPeriod: {
    type: String,
    default: '30d',
  },
  terminalPeriodOptions: {
    type: Array,
    default: () => [],
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
  'toggleCollapse',
  'updateTerminalPeriod',
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

const terminalPeriodLabel = computed(
  () =>
    props.terminalPeriodOptions.find(
      option => option.value === props.terminalPeriod
    )?.label || ''
);

// Counted by the same query that pages the stage, so this covers every stale
// card in the column rather than only the ones already loaded.
const staleCardsCount = computed(() => props.stage.staleCount || 0);

const toggleCollapseOnDoubleClick = () => {
  if (props.editingStageId === props.stage.id) return;

  emit('toggleCollapse');
};
</script>

<template>
  <header
    class="flex min-h-10 flex-col gap-1.5 border-b border-n-weak px-3 py-2"
    :class="[
      editingStageId === stage.id
        ? ''
        : 'stage-drag-handle cursor-grab select-none',
      stageAccent(stage)?.header,
    ]"
    @dblclick="toggleCollapseOnDoubleClick"
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
      <div class="flex min-w-0 items-center justify-between gap-2">
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
            :class="[
              stageAccent(stage)?.title ?? 'text-n-slate-12',
              { 'cursor-pointer hover:text-n-brand': isAdmin },
            ]"
            :title="isAdmin ? t('KANBAN.STAGE_MENU.EDIT') : undefined"
            @click.stop="
              !suppressNextClick && isAdmin && emit('editStage', stage)
            "
          >
            {{ stage.name }}
          </h3>
          <span
            class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ stage.cardsCount }}
          </span>
          <span
            v-if="staleCardsCount"
            data-testid="kanban-stage-stale-count"
            class="size-2 flex-shrink-0 rounded-full bg-n-ruby-9"
            :title="
              t('KANBAN.STAGE_MENU.STALE_COUNT', { count: staleCardsCount })
            "
          />
        </div>

        <div class="flex flex-shrink-0 gap-1">
          <NextButton
            icon="i-lucide-chevrons-right-left"
            ghost
            xs
            slate
            class="no-drag !size-8 !rounded-md"
            :aria-label="t('KANBAN.STAGE.COLLAPSE')"
            :title="t('KANBAN.STAGE.COLLAPSE')"
            @click.stop="emit('toggleCollapse')"
          />
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
      </div>

      <div
        v-if="stage.totalValue > 0 || isTerminalStage(stage)"
        class="flex min-w-0 items-center justify-between gap-2"
      >
        <span
          v-if="stage.totalValue > 0"
          data-testid="kanban-stage-total-value"
          class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          :title="formatCurrency(stage.totalValue)"
        >
          {{ formatCompactCurrency(stage.totalValue) }}
        </span>
        <div
          v-if="isTerminalStage(stage)"
          class="ms-auto w-28 flex-shrink-0"
          @dblclick.stop
        >
          <Select
            :model-value="terminalPeriod"
            :options="terminalPeriodOptions"
            full-width
            class="[&>select]:!px-2 [&>select]:!py-1 [&>select]:!pr-7 [&>select]:text-xs"
            :aria-label="t('KANBAN.STAGE.PERIOD.LABEL')"
            :title="
              t('KANBAN.STAGE.PERIOD_SUMMARY', { period: terminalPeriodLabel })
            "
            @update:model-value="
              value =>
                emit('updateTerminalPeriod', { stageId: stage.id, value })
            "
          />
        </div>
      </div>
    </template>
  </header>
</template>
