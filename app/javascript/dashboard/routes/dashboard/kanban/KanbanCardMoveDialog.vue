<script setup>
import { computed, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Select from 'dashboard/components-next/select/Select.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { getKanbanMoveConsequences } from 'dashboard/helper/kanbanMoveConsequences';
import { normalizeKanbanCardSubject } from 'dashboard/helper/kanbanCardSubject';
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
  // Candidates linked to the same conversation. Only another card with the
  // same origin and normalized subject blocks a target funnel.
  existingCards: {
    type: Array,
    default: () => [],
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
  anotherBoardOnly: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['move', 'close']);
const { t } = useI18n();

// A lookup instead of an interpolated key: the linter cannot follow a dynamic
// one, and every consequence the helper can raise is listed here.
const CONSEQUENCE_LABELS = {
  MOVE_CONFIRM_REOPEN: params => t('KANBAN.CARD.MOVE_CONFIRM_REOPEN', params),
  MOVE_CONFIRM_REASON: params => t('KANBAN.CARD.MOVE_CONFIRM_REASON', params),
  MOVE_CONFIRM_FIELDS: params => t('KANBAN.CARD.MOVE_CONFIRM_FIELDS', params),
  MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES: params =>
    t('KANBAN.CARD.MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES', params),
  MOVE_CONFIRM_RECURRENCE_MAY_RECREATE: params =>
    t('KANBAN.CARD.MOVE_CONFIRM_RECURRENCE_MAY_RECREATE', params),
};

const view = ref('destination');
const selectedStage = ref(null);

const currentBoardId = computed(() =>
  Number(
    props.board?.id ?? props.card.kanbanBoardId ?? props.card.kanbanBoard?.id
  )
);

const {
  boardId: targetBoardId,
  boardOptions,
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

const duplicateCardForBoard = boardId =>
  props.existingCards.find(
    candidate =>
      Number(candidate.id) !== Number(props.card.id) &&
      Number(candidate.kanbanBoardId ?? candidate.kanbanBoard?.id) ===
        Number(boardId) &&
      candidate.origin === props.card.origin &&
      normalizeKanbanCardSubject(candidate.subject) ===
        normalizeKanbanCardSubject(props.card.subject)
  );
const isCurrentBoardUnavailable = computed(
  () => props.anotherBoardOnly && isCurrentBoard.value
);

const boardOptionsWithStatus = computed(() =>
  boardOptions.value.map(option => {
    const isCurrentOption =
      Number(option.value) === Number(currentBoardId.value);
    const otherCard =
      props.anotherBoardOnly && isCurrentOption
        ? null
        : duplicateCardForBoard(option.value);
    const alreadyThere = t('CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD', {
      id: otherCard?.id,
    });

    return {
      ...option,
      disabled: (props.anotherBoardOnly && isCurrentOption) || !!otherCard,
      label: otherCard ? `${option.label} — ${alreadyThere}` : option.label,
    };
  })
);
const blockedTargetCard = computed(() =>
  isCurrentBoardUnavailable.value
    ? null
    : duplicateCardForBoard(targetBoardId.value)
);
const hasSelectableBoard = computed(() =>
  boardOptionsWithStatus.value.some(option => !option.disabled)
);
const hasNoStages = computed(() => !targetStages.value.length);

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
  if (!props.isMoving) emit('close');
};

const onBackdropMouseDown = () => {
  close();
};

watch(targetBoardId, () => {
  selectedStage.value = null;
});

const chooseStage = stage => {
  selectedStage.value = stage;
  view.value = 'confirm';
};

const goBack = () => {
  view.value = 'destination';
  selectedStage.value = null;
};

const submit = () => {
  if (
    !selectedStage.value ||
    !targetBoardId.value ||
    !!blockedTargetCard.value ||
    isCurrentBoardUnavailable.value ||
    props.isMoving
  ) {
    return;
  }

  emit('move', {
    boardId: Number(targetBoardId.value),
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

reset();
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      data-testid="kanban-card-move-dialog"
      class="fixed inset-0 z-[9990] flex items-center justify-center bg-n-alpha-black2 p-4 backdrop-blur-[4px]"
      role="presentation"
      @keydown.esc.stop.prevent="close"
      @mousedown.self="onBackdropMouseDown"
    >
      <section
        class="max-h-[calc(100vh-2rem)] w-full max-w-md overflow-y-auto rounded-xl border border-n-weak bg-n-surface-1 text-n-slate-12 shadow-xl"
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
            class="flex size-7 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
            :disabled="isMoving"
            @click="close"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </header>

        <div v-if="view === 'destination'" class="space-y-3 p-4">
          <label
            v-if="boardOptionsWithStatus.length"
            class="block text-xs font-medium text-n-slate-11"
          >
            {{ t('KANBAN.CARD.MOVE_BOARD_LABEL') }}
            <Select
              v-model="targetBoardId"
              data-testid="kanban-card-move-dialog-board"
              :options="boardOptionsWithStatus"
              full-width
              class="mt-1 font-normal"
              :disabled="isMoving"
            />
          </label>

          <p
            v-if="!hasSelectableBoard"
            data-testid="kanban-card-move-dialog-no-board"
            class="mb-0 text-sm text-n-slate-10"
          >
            {{ t('CONVERSATION_SIDEBAR.KANBAN.NO_OTHER_BOARDS') }}
          </p>
          <p
            v-else-if="blockedTargetCard"
            data-testid="kanban-card-move-dialog-taken"
            class="mb-0 text-sm text-n-slate-10"
          >
            {{
              t('CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD', {
                id: blockedTargetCard.id,
              })
            }}
          </p>
          <p
            v-else-if="!isCurrentBoardUnavailable && hasNoStages"
            data-testid="kanban-card-move-dialog-empty"
            class="mb-0 text-sm text-n-slate-10"
          >
            {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
          </p>
          <div v-else-if="!isCurrentBoardUnavailable" class="grid gap-1">
            <button
              v-for="stage in targetStages"
              :key="stage.id"
              type="button"
              data-testid="kanban-card-move-dialog-stage"
              class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="isMoving"
              @click="chooseStage(stage)"
            >
              <span
                class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9"
                :style="stage.color ? { backgroundColor: stage.color } : null"
              />
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
              {{ CONSEQUENCE_LABELS[consequence.key](consequence.params) }}
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
              v-if="!isMoving"
              type="button"
              data-testid="kanban-card-move-dialog-back"
              class="rounded-md px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-2"
              @click="goBack"
            >
              {{ t('KANBAN.MENU.BACK') }}
            </button>
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
          </div>
        </div>
      </section>
    </div>
  </TeleportWithDirection>
</template>
