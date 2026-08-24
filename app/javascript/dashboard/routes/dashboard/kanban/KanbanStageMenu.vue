<script setup>
import { computed, nextTick, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKanbanMoveTarget } from 'dashboard/composables/useKanbanMoveTarget';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import Input from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import KanbanMenuHeader from './KanbanMenuHeader.vue';
import {
  MENU_DIVIDER_CLASSES,
  MENU_OPTION_CLASSES,
  MENU_OPTION_DESTRUCTIVE_CLASSES,
} from './menuClasses';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  boards: {
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
  isAdmin: {
    type: Boolean,
    default: false,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'addCard',
  'edit',
  'copy',
  'move',
  'moveCards',
  'sort',
  'deleteStage',
  'deleteCards',
]);

const { t } = useI18n();
const view = ref('root');
const copyName = ref('');
const copyNameInput = ref(null);
const targetPosition = ref(1);

const currentBoardId = computed(() => Number(props.stage.kanbanBoardId));
const viewTitle = computed(() => {
  switch (view.value) {
    case 'copy':
      return t('KANBAN.STAGE_MENU.COPY.TITLE');
    case 'move':
      return t('KANBAN.STAGE_MENU.MOVE.TITLE');
    case 'moveCards':
      return t('KANBAN.STAGE_MENU.MOVE_CARDS.TITLE');
    case 'sort':
      return t('KANBAN.STAGE_MENU.SORT.TITLE');
    default:
      return t('KANBAN.STAGE_MENU.TITLE');
  }
});
const { isTerminalStage } = useKanbanStageOrder({
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
  lostStageId: toRef(props, 'lostStageId'),
});
const isCurrentStageTerminal = computed(() => isTerminalStage(props.stage));
// Sending this stage's cards somewhere and sending the stage itself both pick a funnel and
// then a slot among its regular stages, so they read the same way from one set of inputs and
// only keep their own selection apart.
const moveTargetInputs = {
  boards: toRef(props, 'boards'),
  currentBoardId,
  excludeStageId: computed(() => props.stage.id),
  lostStageId: toRef(props, 'lostStageId'),
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
};
const {
  boardId: moveCardsBoardId,
  boardOptions: moveCardsTargetBoardOptions,
  isCurrentBoard: isCurrentMoveCardsBoard,
  reset: resetMoveCardsTarget,
  targetStages: cardMoveTargets,
} = useKanbanMoveTarget(moveTargetInputs);
const {
  boardId: stageMoveBoardId,
  reset: resetStageMoveTarget,
  sourceBoard: currentBoard,
  targetStages: stageMoveTargets,
} = useKanbanMoveTarget(moveTargetInputs);
// The picker leaves this stage out of its own board's list, so either way the destination
// offers one more slot than the regular stages it already shows.
const positionOptions = computed(() =>
  Array.from(
    { length: stageMoveTargets.value.length + 1 },
    (_, index) => index + 1
  )
);
const positionSelectOptions = computed(() =>
  positionOptions.value.map(position => ({
    value: position,
    label: t('KANBAN.STAGE_MENU.MOVE.POSITION_VALUE', { position }),
  }))
);
const cardCount = computed(() => {
  const summary = currentBoard.value?.stagesSummary?.find(
    stage => Number(stage.id) === Number(props.stage.id)
  );

  return summary?.cardsCount ?? props.stage.cardsCount ?? 0;
});
const hasCards = computed(() => cardCount.value > 0);
const canMoveToAnotherBoard = computed(() => !isCurrentStageTerminal.value);
// Archived funnels are not somewhere a stage can be sent, and the slot count below is read
// from the same list the picker offers.
const moveDestinationBoards = computed(() => {
  const boards = props.boards.filter(board => board.active !== false);

  return canMoveToAnotherBoard.value
    ? boards
    : boards.filter(board => Number(board.id) === currentBoardId.value);
});
const moveDestinationBoardOptions = computed(() =>
  moveDestinationBoards.value.map(board => ({
    value: board.id,
    label: board.name,
  }))
);
const canDeleteStage = computed(
  () => props.stages.length > 1 && !isCurrentStageTerminal.value
);
const sortOptions = computed(() => [
  {
    value: 'created_at_desc',
    label: t('KANBAN.STAGE_MENU.SORT.NEWEST'),
  },
  {
    value: 'created_at_asc',
    label: t('KANBAN.STAGE_MENU.SORT.OLDEST'),
  },
  { value: 'name_asc', label: t('KANBAN.STAGE_MENU.SORT.NAME') },
]);

const resetView = () => {
  view.value = 'root';
  copyName.value = '';
  targetPosition.value = 1;
  resetStageMoveTarget();
  resetMoveCardsTarget();
};

const openView = nextView => {
  view.value = nextView;

  if (nextView === 'copy') {
    copyName.value = props.stage.name;
    nextTick(() => copyNameInput.value?.$el?.querySelector('input')?.select());
  }

  if (nextView === 'move') {
    resetStageMoveTarget();
    targetPosition.value = 1;
  }

  if (nextView === 'moveCards') resetMoveCardsTarget();
};

const closeMenu = hide => {
  resetView();
  hide();
};

const emitAction = (event, payload, hide) => {
  switch (event) {
    case 'addCard':
      emit('addCard');
      break;
    case 'edit':
      emit('edit');
      break;
    case 'copy':
      emit('copy', payload);
      break;
    case 'move':
      emit('move', payload);
      break;
    case 'moveCards':
      emit('moveCards', payload);
      break;
    case 'sort':
      emit('sort', payload);
      break;
    case 'deleteStage':
      emit('deleteStage');
      break;
    case 'deleteCards':
      emit('deleteCards');
      break;
    default:
      return;
  }

  closeMenu(hide);
};

const submitCopy = hide => {
  const name = copyName.value.trim();
  if (!name) return;

  emitAction('copy', { name }, hide);
};

const submitMove = hide => {
  emitAction(
    'move',
    {
      kanbanBoardId: Number(stageMoveBoardId.value),
      position: Number(targetPosition.value),
    },
    hide
  );
};

const submitMoveCards = (targetStage, hide) => {
  const payload = { targetStageId: targetStage.id };
  if (!isCurrentMoveCardsBoard.value) {
    payload.targetBoardId = Number(moveCardsBoardId.value);
  }

  emitAction('moveCards', payload, hide);
};

watch(stageMoveBoardId, () => {
  targetPosition.value = 1;
});
</script>

<template>
  <Popover align="start" disable-mobile-view @hide="resetView">
    <button
      type="button"
      data-testid="kanban-stage-menu-trigger"
      class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="isBusy"
      :aria-label="t('KANBAN.STAGE_MENU.TITLE')"
      :title="t('KANBAN.STAGE_MENU.TITLE')"
    >
      <i class="i-lucide-more-horizontal size-4" />
    </button>

    <template #content="{ hide }">
      <div
        data-testid="kanban-stage-menu"
        class="w-72 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl text-sm text-n-slate-12"
      >
        <KanbanMenuHeader
          :title="viewTitle"
          :show-back="view !== 'root'"
          @back="view = 'root'"
          @close="closeMenu(hide)"
        />

        <div v-if="view === 'root'" class="p-2">
          <button
            v-if="!isCurrentStageTerminal"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="emitAction('addCard', undefined, hide)"
          >
            <i class="i-lucide-plus size-4" />
            {{ t('KANBAN.STAGE_MENU.ADD_CARD') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="emitAction('edit', undefined, hide)"
          >
            <i class="i-lucide-pencil size-4" />
            {{ t('KANBAN.STAGE_MENU.EDIT') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="openView('copy')"
          >
            <i class="i-lucide-copy size-4" />
            {{ t('KANBAN.STAGE_MENU.COPY.LABEL') }}
          </button>
          <button
            v-if="isAdmin && !isCurrentStageTerminal"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="openView('move')"
          >
            <i class="i-lucide-arrow-right-left size-4" />
            {{ t('KANBAN.STAGE_MENU.MOVE.LABEL') }}
          </button>
          <button
            v-if="!isCurrentStageTerminal && hasCards"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="openView('moveCards')"
          >
            <i class="i-lucide-forward size-4" />
            {{ t('KANBAN.STAGE_MENU.MOVE_CARDS.LABEL') }}
          </button>
          <button
            v-if="hasCards"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="openView('sort')"
          >
            <i class="i-lucide-arrow-down-up size-4" />
            {{ t('KANBAN.STAGE_MENU.SORT.LABEL') }}
          </button>
          <div
            v-if="isAdmin && (canDeleteStage || hasCards)"
            :class="MENU_DIVIDER_CLASSES"
          />
          <button
            v-if="isAdmin && canDeleteStage"
            type="button"
            :class="[MENU_OPTION_CLASSES, MENU_OPTION_DESTRUCTIVE_CLASSES]"
            :disabled="isBusy"
            @click="emitAction('deleteStage', undefined, hide)"
          >
            <i class="i-lucide-trash size-4" />
            {{ t('KANBAN.STAGE_MENU.DELETE_STAGE') }}
          </button>
          <button
            v-if="isAdmin && hasCards"
            type="button"
            :class="[MENU_OPTION_CLASSES, MENU_OPTION_DESTRUCTIVE_CLASSES]"
            :disabled="isBusy"
            @click="emitAction('deleteCards', undefined, hide)"
          >
            <i class="i-lucide-trash-2 size-4" />
            {{ t('KANBAN.STAGE_MENU.DELETE_CARDS') }}
          </button>
        </div>

        <form
          v-else-if="view === 'copy'"
          class="space-y-4 p-4"
          @submit.prevent="submitCopy(hide)"
        >
          <Input
            ref="copyNameInput"
            v-model="copyName"
            :label="t('KANBAN.STAGE_MENU.COPY.NAME')"
          />
          <button
            type="submit"
            class="w-full rounded-md bg-n-brand px-3 py-2 font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!copyName.trim() || isBusy"
          >
            {{ t('KANBAN.STAGE_MENU.COPY.SUBMIT') }}
          </button>
        </form>

        <form
          v-else-if="view === 'move'"
          class="space-y-4 p-4"
          @submit.prevent="submitMove(hide)"
        >
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.STAGE_MENU.MOVE.BOARD') }}
            <Select
              v-model="stageMoveBoardId"
              :options="moveDestinationBoardOptions"
              full-width
              class="mt-1 font-normal"
            />
          </label>
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.STAGE_MENU.MOVE.POSITION') }}
            <Select
              v-model="targetPosition"
              :options="positionSelectOptions"
              full-width
              class="mt-1 font-normal"
            />
          </label>
          <button
            type="submit"
            class="w-full rounded-md bg-n-brand px-3 py-2 font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!stageMoveBoardId || isBusy"
          >
            {{ t('KANBAN.STAGE_MENU.MOVE.SUBMIT') }}
          </button>
        </form>

        <div v-else-if="view === 'moveCards'" class="space-y-2 p-2">
          <label class="block px-2 text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.CARD.MOVE_BOARD_LABEL') }}
            <Select
              v-model="moveCardsBoardId"
              data-testid="kanban-stage-move-cards-board"
              :options="moveCardsTargetBoardOptions"
              full-width
              class="mt-1 font-normal"
            />
          </label>
          <div :class="MENU_DIVIDER_CLASSES" />
          <p
            v-if="cardMoveTargets.length === 0"
            class="px-2 py-3 text-sm text-n-slate-10"
          >
            {{ t('KANBAN.STAGE_MENU.MOVE_CARDS.EMPTY') }}
          </p>
          <button
            v-for="targetStage in cardMoveTargets"
            :key="targetStage.id"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="submitMoveCards(targetStage, hide)"
          >
            <span
              class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9"
              :style="{ backgroundColor: targetStage.color }"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1 truncate">{{ targetStage.name }}</span>
            <span class="flex-shrink-0 text-xs text-n-slate-10">
              {{ t('KANBAN.STAGE_MENU.MOVE_CARDS.TARGET') }}
            </span>
          </button>
        </div>

        <div v-else-if="view === 'sort'" class="p-2">
          <button
            v-for="option in sortOptions"
            :key="option.value"
            type="button"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="emitAction('sort', { sortBy: option.value }, hide)"
          >
            {{ option.label }}
          </button>
        </div>
      </div>
    </template>
  </Popover>
</template>
