<script setup>
import { computed, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import Select from 'dashboard/components-next/select/Select.vue';
import { getKanbanMoveConsequences } from 'dashboard/helper/kanbanMoveConsequences';
import { useKanbanMoveTarget } from 'dashboard/composables/useKanbanMoveTarget';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  boards: {
    type: Array,
    default: () => [],
  },
  board: {
    type: Object,
    default: () => ({}),
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
  inboxId: {
    type: [Number, String],
    default: null,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  isMoving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['move', 'close']);
const { t } = useI18n();

const view = ref('destination');
const selectedStage = ref(null);
const currentBoardId = computed(() => Number(props.board?.id));
const {
  boardId: moveBoardId,
  boardOptions: moveBoardOptions,
  isCurrentBoard,
  reset: resetMoveTarget,
  selectedBoard,
  sourceBoard,
  targetStages,
} = useKanbanMoveTarget({
  board: toRef(props, 'board'),
  boards: toRef(props, 'boards'),
  currentBoardId,
  excludeStageId: null,
  inboxId: toRef(props, 'inboxId'),
  lostStageId: toRef(props, 'lostStageId'),
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
});

const moveConsequences = computed(() => {
  if (isCurrentBoard.value) return [];

  return getKanbanMoveConsequences({
    card: props.card,
    sourceBoard: sourceBoard.value,
    targetBoard: selectedBoard.value,
    reasons: props.reasons,
  });
});

const reset = () => {
  view.value = 'destination';
  selectedStage.value = null;
  resetMoveTarget();
};

const close = () => {
  emit('close');
};

const onBoardChanged = () => {
  selectedStage.value = null;
};

const chooseStage = stage => {
  selectedStage.value = stage;
  view.value = 'confirm';
};

const goBack = () => {
  view.value = 'destination';
  selectedStage.value = null;
};

const submit = () => {
  if (!selectedStage.value || !moveBoardId.value || props.isMoving) return;

  emit('move', {
    boardId: Number(moveBoardId.value),
    stageId: Number(selectedStage.value.id),
  });
};

const stageLabel = stage => {
  if (
    isCurrentBoard.value &&
    Number(stage.id) === Number(props.card.kanbanStageId)
  ) {
    return t('KANBAN.CARD.MOVE_CURRENT_STAGE', { name: stage.name });
  }

  return stage.name;
};

const hasNoStages = computed(() => !targetStages.value.length);

reset();
</script>

<template>
  <div
    data-testid="kanban-card-move-dialog"
    class="absolute inset-0 z-20 flex items-start justify-center bg-n-alpha-black2 p-4"
    role="presentation"
    @keydown.esc.stop.prevent="close"
    @mousedown.self="close"
  >
    <section
      class="w-full max-w-md rounded-xl border border-n-weak bg-n-surface-1 text-n-slate-12 shadow-xl"
      role="dialog"
      aria-modal="true"
      :aria-label="t('KANBAN.CARD.MOVE_TO')"
    >
      <header
        class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
      >
        <h2 class="mb-0 text-sm font-semibold">
          {{ t('KANBAN.CARD.MOVE_TO') }}
        </h2>
        <button
          type="button"
          data-testid="kanban-card-move-dialog-close"
          class="flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
          @click="close"
        >
          <i class="i-lucide-x size-4" />
        </button>
      </header>

      <div v-if="view === 'destination'" class="space-y-3 p-4">
        <label
          v-if="moveBoardOptions.length"
          class="block text-xs font-medium text-n-slate-11"
        >
          {{ t('KANBAN.CARD.MOVE_BOARD_LABEL') }}
          <Select
            v-model="moveBoardId"
            data-testid="kanban-card-move-dialog-board"
            :options="moveBoardOptions"
            full-width
            class="mt-1 font-normal"
            :disabled="isMoving"
            @update:model-value="onBoardChanged"
          />
        </label>

        <p
          v-if="hasNoStages"
          data-testid="kanban-card-move-dialog-empty"
          class="mb-0 text-sm text-n-slate-10"
        >
          {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
        </p>
        <div v-else class="grid gap-1">
          <button
            v-for="stage in targetStages"
            :key="stage.id"
            type="button"
            data-testid="kanban-card-move-dialog-stage"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isMoving"
            @click="chooseStage(stage)"
          >
            <span class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9" />
            <span class="min-w-0 truncate">{{ stageLabel(stage) }}</span>
          </button>
        </div>
      </div>

      <div v-else class="space-y-4 p-4">
        <div>
          <p class="mb-1 text-xs text-n-slate-11">
            {{ selectedBoard.name }}
          </p>
          <p
            data-testid="kanban-card-move-dialog-selected-stage"
            class="mb-0 font-medium"
          >
            {{ stageLabel(selectedStage) }}
          </p>
        </div>

        <ul
          v-if="moveConsequences.length"
          data-testid="kanban-card-move-dialog-consequences"
          class="m-0 grid list-disc gap-2 pl-5 text-sm text-n-slate-11"
        >
          <li v-for="consequence in moveConsequences" :key="consequence.key">
            {{ t(`KANBAN.CARD.${consequence.key}`, consequence.params) }}
          </li>
        </ul>
        <p
          v-else-if="!isCurrentBoard"
          data-testid="kanban-card-move-dialog-clean"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.CARD.MOVE_CONFIRM_CLEAN') }}
        </p>

        <div class="flex items-center justify-end gap-2">
          <button
            type="button"
            data-testid="kanban-card-move-dialog-cancel"
            class="rounded-md px-3 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
            :disabled="isMoving"
            @click="close"
          >
            {{ t('KANBAN.CARD.MOVE_CONFIRM_CANCEL') }}
          </button>
          <button
            type="button"
            data-testid="kanban-card-move-dialog-submit"
            class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isMoving"
            @click="submit"
          >
            <i
              v-if="isMoving"
              class="i-lucide-loader-circle mr-1 inline-block size-4 animate-spin"
            />
            {{ t('KANBAN.CARD.MOVE_CONFIRM_SUBMIT') }}
          </button>
          <button
            v-if="!isMoving"
            type="button"
            data-testid="kanban-card-move-dialog-back"
            class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
            @click="goBack"
          >
            {{ t('KANBAN.MENU.BACK') }}
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
