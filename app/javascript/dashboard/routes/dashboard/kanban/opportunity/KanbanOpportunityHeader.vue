<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import KanbanCardStatusBadge from '../KanbanCardStatusBadge.vue';

const props = defineProps({
  card: {
    type: Object,
    default: null,
  },
  cardDisplayId: {
    type: [Number, String],
    default: null,
  },
  hasUnsavedChanges: {
    type: Boolean,
    default: false,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  lostStageId: {
    type: Number,
    default: null,
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  // Resolves to false when the move was rejected, so the select can revert.
  moveToStage: {
    type: Function,
    required: true,
  },
});

const emit = defineEmits([
  'changeStatus',
  'stageMoved',
  'copyCardId',
  'removeCard',
  'close',
]);

const { t } = useI18n();

const isMovingStage = ref(false);
const stageSelection = ref(props.card?.kanbanStageId || '');

const isTerminalStage = stage =>
  Number(stage.id) === Number(props.wonStageId) ||
  Number(stage.id) === Number(props.lostStageId);

// Terminal stages are only reachable through the status badge, which validates
// the reason and the transition; the select lists regular stages only.
const stageOptions = computed(() => {
  const options = props.stages
    .filter(stage => !isTerminalStage(stage))
    .map(stage => ({ value: stage.id, label: stage.name }));
  const currentStage = props.stages.find(
    stage => Number(stage.id) === Number(props.card?.kanbanStageId)
  );

  if (currentStage && isTerminalStage(currentStage)) {
    options.push({
      value: currentStage.id,
      label: currentStage.name,
      disabled: true,
    });
  }

  return options;
});

watch(
  () => props.card?.kanbanStageId,
  stageId => {
    stageSelection.value = stageId || '';
  }
);

const onStageChanged = async stageId => {
  const targetStageId = Number(stageId);
  const currentStageId = Number(props.card?.kanbanStageId);
  if (!targetStageId || targetStageId === currentStageId) return;

  isMovingStage.value = true;
  const moved = await props.moveToStage(props.card, targetStageId);
  isMovingStage.value = false;

  if (moved === false) {
    stageSelection.value = currentStageId || '';
    return;
  }

  emit('stageMoved', targetStageId);
};
</script>

<template>
  <header
    class="flex flex-none items-start justify-between gap-4 border-b border-n-weak px-4 py-4"
  >
    <div class="min-w-0 flex-1">
      <div class="flex min-w-0 items-center gap-2">
        <h2
          id="kanban-opportunity-title"
          data-testid="kanban-opportunity-title"
          class="mb-0 truncate text-base font-semibold text-n-slate-12"
        >
          {{ card?.subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE') }}
        </h2>
        <span
          v-if="hasUnsavedChanges"
          data-testid="kanban-opportunity-unsaved-indicator"
          class="inline-flex flex-shrink-0 items-center gap-1.5 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
        >
          <span class="size-1.5 rounded-full bg-n-amber-9" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_INDICATOR') }}
        </span>
      </div>
      <div v-if="card" class="mt-2 flex min-w-0 flex-wrap items-center gap-2">
        <KanbanCardStatusBadge
          v-if="wonStageId && lostStageId"
          :kanban-stage-id="card.kanbanStageId"
          :won-stage-id="wonStageId"
          :lost-stage-id="lostStageId"
          :reasons="reasons"
          :lost-reason-required="lostReasonRequired"
          @change="emit('changeStatus', $event)"
        />
        <Select
          v-if="stageOptions.length"
          v-model="stageSelection"
          data-testid="kanban-opportunity-stage-select"
          :options="stageOptions"
          :disabled="isMovingStage"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.MOVE_TO_STAGE')"
          @update:model-value="onStageChanged"
        />
      </div>
    </div>
    <div v-if="cardDisplayId" class="flex flex-shrink-0 items-center gap-1">
      <span
        data-testid="kanban-opportunity-card-id"
        class="text-sm font-medium text-n-slate-11"
      >
        {{ t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID', { id: cardDisplayId }) }}
      </span>
      <Popover align="end" disable-mobile-view :show-content-border="false">
        <button
          type="button"
          data-testid="kanban-opportunity-more-actions"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.MORE_ACTIONS')"
        >
          <i class="i-lucide-ellipsis-vertical size-4" />
        </button>
        <template #content>
          <div class="grid min-w-40 gap-1 rounded-lg p-1">
            <button
              type="button"
              data-testid="kanban-opportunity-copy-card-id"
              class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID')"
              @click="emit('copyCardId')"
            >
              <i class="i-lucide-copy size-4" />
              {{ t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID') }}
            </button>
            <button
              v-if="card"
              type="button"
              data-testid="kanban-opportunity-remove-card"
              class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-ruby-11 hover:bg-n-ruby-2"
              :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
              :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
              @click="emit('removeCard', card)"
            >
              <i class="i-lucide-trash size-4" />
              {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
            </button>
          </div>
        </template>
      </Popover>
      <button
        type="button"
        data-testid="kanban-opportunity-close"
        class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
        :title="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
        @click="emit('close')"
      >
        <i class="i-lucide-x size-4" />
      </button>
    </div>
  </header>
</template>
