<script setup>
import { computed, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Select from 'dashboard/components-next/select/Select.vue';
import { getKanbanMoveConsequences } from 'dashboard/helper/kanbanMoveConsequences';
import { useKanbanMoveTarget } from 'dashboard/composables/useKanbanMoveTarget';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  cards: {
    type: Array,
    default: () => [],
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
    type: [Number, String],
    default: null,
  },
  lostStageId: {
    type: [Number, String],
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
const consequenceLabel = consequence => {
  switch (consequence.key) {
    case 'MOVE_CONFIRM_REOPEN':
      return t('KANBAN.CARD.MOVE_CONFIRM_REOPEN', consequence.params);
    case 'MOVE_CONFIRM_REASON':
      return t('KANBAN.CARD.MOVE_CONFIRM_REASON', consequence.params);
    case 'MOVE_CONFIRM_FIELDS':
      return t('KANBAN.CARD.MOVE_CONFIRM_FIELDS', consequence.params);
    case 'MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES':
      return t(
        'KANBAN.CARD.MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES',
        consequence.params
      );
    case 'MOVE_CONFIRM_RECURRENCE_MAY_RECREATE':
      return t(
        'KANBAN.CARD.MOVE_CONFIRM_RECURRENCE_MAY_RECREATE',
        consequence.params
      );
    default:
      return '';
  }
};

const step = ref(1);
const selectedStage = ref(null);

const currentBoardId = computed(() =>
  Number(
    props.board?.id ??
      props.card.kanbanBoardId ??
      props.card.kanban_board_id ??
      props.card.kanbanBoard?.id ??
      props.card.kanban_board?.id
  )
);
const currentStageId = computed(() =>
  Number(
    props.card.kanbanStageId ??
      props.card.kanban_stage_id ??
      props.card.kanbanStage?.id ??
      props.card.kanban_stage?.id
  )
);
const sourceWonStageId = computed(
  () => props.board?.wonStageId ?? props.board?.won_stage_id ?? props.wonStageId
);
const sourceLostStageId = computed(
  () =>
    props.board?.lostStageId ?? props.board?.lost_stage_id ?? props.lostStageId
);

const {
  boardId: selectedBoardId,
  boardOptions,
  isCurrentBoard,
  selectedBoard,
  sourceBoard,
  targetStages,
} = useKanbanMoveTarget({
  board: toRef(props, 'board'),
  boards: toRef(props, 'boards'),
  currentBoardId,
  excludeStageId: currentStageId,
  inboxId: toRef(props, 'inboxId'),
  lostStageId: sourceLostStageId,
  stages: toRef(props, 'stages'),
  wonStageId: sourceWonStageId,
});

const cardBoardId = card =>
  card?.kanbanBoardId ??
  card?.kanban_board_id ??
  card?.kanbanBoard?.id ??
  card?.kanban_board?.id;
const existingCardForBoard = boardId =>
  props.cards.find(
    card =>
      Number(cardBoardId(card)) === Number(boardId) &&
      Number(card.id) !== Number(props.card.id)
  ) || props.cards.find(card => Number(cardBoardId(card)) === Number(boardId));

const boardOptionsWithStatus = computed(() =>
  boardOptions.value.map(option => {
    const existingCard = existingCardForBoard(option.value);
    const isCurrent = Number(option.value) === currentBoardId.value;
    const disabledReason = existingCard
      ? t('CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD', {
          id: existingCard.id,
        })
      : '';

    return {
      ...option,
      disabled: isCurrent || !!existingCard,
      label: disabledReason
        ? `${option.label} — ${disabledReason}`
        : option.label,
    };
  })
);
const selectableBoardOptions = computed(() =>
  boardOptionsWithStatus.value.filter(option => !option.disabled)
);
const regularTargetStages = computed(() =>
  targetStages.value.filter(stage => stage.active !== false)
);
const canChooseTargetBoard = computed(
  () =>
    !isCurrentBoard.value &&
    !!selectedBoard.value?.id &&
    !existingCardForBoard(selectedBoard.value.id)
);
const canContinueToStage = computed(
  () => canChooseTargetBoard.value && selectableBoardOptions.value.length > 0
);
const canContinueToReview = computed(() => !!selectedStage.value);
const moveConsequences = computed(() =>
  getKanbanMoveConsequences({
    card: props.card,
    sourceBoard: sourceBoard.value,
    targetBoard: selectedBoard.value,
    reasons: props.reasons,
  })
);

watch(selectedBoardId, () => {
  selectedStage.value = null;
});

const close = () => {
  if (!props.isMoving) emit('close');
};
const goToStages = () => {
  if (canContinueToStage.value) step.value = 2;
};
const chooseStage = stage => {
  selectedStage.value = stage;
  step.value = 3;
};
const goBack = () => {
  step.value = Math.max(step.value - 1, 1);
};
const submit = () => {
  if (!canContinueToReview.value || !canChooseTargetBoard.value) return;

  emit('move', {
    boardId: Number(selectedBoardId.value),
    stageId: Number(selectedStage.value.id),
  });
};
</script>

<template>
  <div
    data-testid="kanban-conversation-move-dialog"
    class="absolute inset-0 z-20 flex items-start justify-center bg-n-alpha-black2 p-3"
    role="presentation"
    @keydown.esc.stop.prevent="close"
    @mousedown.self="close"
  >
    <section
      class="w-full max-w-md rounded-xl border border-n-weak bg-n-surface-1 text-n-slate-12 shadow-xl"
      role="dialog"
      aria-modal="true"
      :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD')"
    >
      <header
        class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
      >
        <div class="min-w-0">
          <h2 class="mb-1 text-sm font-semibold">
            {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD') }}
          </h2>
          <ol
            class="m-0 flex list-none gap-2 p-0 text-xs text-n-slate-10"
            :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_STEPS')"
          >
            <li :class="{ 'font-medium text-n-brand': step === 1 }">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_BOARD') }}
            </li>
            <li :class="{ 'font-medium text-n-brand': step === 2 }">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_STAGE') }}
            </li>
            <li :class="{ 'font-medium text-n-brand': step === 3 }">
              {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_REVIEW') }}
            </li>
          </ol>
        </div>
        <button
          type="button"
          data-testid="kanban-conversation-move-dialog-close"
          class="flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
          :disabled="isMoving"
          @click="close"
        >
          <i class="i-lucide-x size-4" />
        </button>
      </header>

      <div v-if="step === 1" class="grid gap-4 p-4">
        <label class="grid gap-1 text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
          <Select
            v-model="selectedBoardId"
            data-testid="kanban-conversation-move-dialog-board"
            :options="boardOptionsWithStatus"
            :placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD')"
            full-width
            class="mt-1 font-normal"
            :disabled="isMoving || !boardOptionsWithStatus.length"
          />
        </label>
        <p
          v-if="!selectableBoardOptions.length"
          data-testid="kanban-conversation-move-dialog-no-board"
          class="mb-0 text-sm text-n-slate-10"
        >
          {{ t('CONVERSATION_SIDEBAR.KANBAN.NO_OTHER_BOARDS') }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
            :disabled="isMoving"
            @click="close"
          >
            {{ t('KANBAN.CARD.MOVE_CONFIRM_CANCEL') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-move-dialog-next-board"
            class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!canContinueToStage || isMoving"
            @click="goToStages"
          >
            {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_NEXT') }}
          </button>
        </div>
      </div>

      <div v-else-if="step === 2" class="grid gap-4 p-4">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ selectedBoard.name }}
        </p>
        <div
          v-if="regularTargetStages.length"
          class="grid gap-1"
          data-testid="kanban-conversation-move-dialog-stages"
        >
          <button
            v-for="stageOption in regularTargetStages"
            :key="stageOption.id"
            type="button"
            data-testid="kanban-conversation-move-dialog-stage"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isMoving"
            @click="chooseStage(stageOption)"
          >
            <span class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9" />
            <span class="min-w-0 truncate">{{ stageOption.name }}</span>
          </button>
        </div>
        <p
          v-else
          data-testid="kanban-conversation-move-dialog-no-stage"
          class="mb-0 text-sm text-n-slate-10"
        >
          {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
            :disabled="isMoving"
            @click="goBack"
          >
            {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BACK') }}
          </button>
        </div>
      </div>

      <div v-else class="grid gap-4 p-4">
        <div>
          <p class="mb-1 text-xs text-n-slate-11">
            {{ selectedBoard.name }}
          </p>
          <p
            data-testid="kanban-conversation-move-dialog-selected-stage"
            class="mb-0 font-medium"
          >
            {{ selectedStage.name }}
          </p>
        </div>
        <ul
          v-if="moveConsequences.length"
          data-testid="kanban-conversation-move-dialog-consequences"
          class="m-0 grid list-disc gap-2 pl-5 text-sm text-n-slate-11"
        >
          <li v-for="consequence in moveConsequences" :key="consequence.key">
            {{ consequenceLabel(consequence) }}
          </li>
        </ul>
        <p
          v-else
          data-testid="kanban-conversation-move-dialog-clean"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.CARD.MOVE_CONFIRM_CLEAN') }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
            :disabled="isMoving"
            @click="goBack"
          >
            {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BACK') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-move-dialog-cancel"
            class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
            :disabled="isMoving"
            @click="close"
          >
            {{ t('KANBAN.CARD.MOVE_CONFIRM_CANCEL') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-move-dialog-submit"
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
        </div>
      </div>
    </section>
  </div>
</template>
