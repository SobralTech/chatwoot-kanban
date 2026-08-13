<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

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
  activeActionKey: {
    type: String,
    default: '',
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
const targetBoardId = ref(null);
const targetPosition = ref(1);

const currentBoardId = computed(
  () => props.stage.kanbanBoardId || props.stage.kanban_board_id
);
const targetBoard = computed(() =>
  props.boards.find(board => board.id === Number(targetBoardId.value))
);
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
const regularStages = computed(() =>
  props.stages.filter(
    stage => stage.id !== props.wonStageId && stage.id !== props.lostStageId
  )
);
const targetBoardStageCount = computed(() => {
  if (Number(targetBoardId.value) === currentBoardId.value) {
    return props.stages.length;
  }

  return (
    targetBoard.value?.stagesSummary?.length ||
    targetBoard.value?.stages_summary?.length ||
    0
  );
});
const positionOptions = computed(() =>
  Array.from(
    { length: targetBoardStageCount.value + 1 },
    (_, index) => index + 1
  )
);
const cardCount = computed(
  () => props.stage.cardsCount ?? props.stage.cards_count ?? 0
);
const canMoveToAnotherBoard = computed(() => cardCount.value === 0);
const isBusy = computed(() => !!props.activeActionKey);
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
  targetBoardId.value = null;
  targetPosition.value = 1;
};

const openView = nextView => {
  view.value = nextView;

  if (nextView === 'copy') {
    copyName.value = props.stage.name;
    nextTick(() => copyNameInput.value?.$el?.querySelector('input')?.select());
  }

  if (nextView === 'move') {
    targetBoardId.value = currentBoardId.value;
    targetPosition.value = 1;
  }
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
      kanbanBoardId: Number(targetBoardId.value),
      position: Number(targetPosition.value),
    },
    hide
  );
};

watch(targetBoardId, () => {
  targetPosition.value = 1;
});
</script>

<template>
  <Popover align="end" disable-mobile-view @hide="resetView">
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
        <header class="flex items-center border-b border-n-weak px-2 py-2">
          <button
            v-if="view !== 'root'"
            type="button"
            class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('KANBAN.STAGE_MENU.BACK')"
            @click="view = 'root'"
          >
            <i class="i-lucide-chevron-left size-4" />
          </button>
          <span v-else class="size-8" />
          <h2 class="min-w-0 flex-1 truncate text-center text-sm font-semibold">
            {{ viewTitle }}
          </h2>
          <button
            type="button"
            class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('KANBAN.STAGE_MENU.CLOSE')"
            @click="closeMenu(hide)"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </header>

        <div v-if="view === 'root'" class="p-1">
          <button
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="emitAction('addCard', undefined, hide)"
          >
            <i class="i-lucide-plus size-4" />
            {{ t('KANBAN.STAGE_MENU.ADD_CARD') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="emitAction('edit', undefined, hide)"
          >
            <i class="i-lucide-pencil size-4" />
            {{ t('KANBAN.STAGE_MENU.EDIT') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="openView('copy')"
          >
            <i class="i-lucide-copy size-4" />
            {{ t('KANBAN.STAGE_MENU.COPY.LABEL') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="openView('move')"
          >
            <i class="i-lucide-arrow-right-left size-4" />
            {{ t('KANBAN.STAGE_MENU.MOVE.LABEL') }}
          </button>
          <button
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="openView('moveCards')"
          >
            <i class="i-lucide-forward size-4" />
            {{ t('KANBAN.STAGE_MENU.MOVE_CARDS.LABEL') }}
          </button>
          <button
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="openView('sort')"
          >
            <i class="i-lucide-arrow-down-up size-4" />
            {{ t('KANBAN.STAGE_MENU.SORT.LABEL') }}
          </button>
          <div v-if="isAdmin" class="my-1 border-t border-n-weak" />
          <button
            v-if="isAdmin"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-n-ruby-11 hover:bg-n-ruby-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="emitAction('deleteStage', undefined, hide)"
          >
            <i class="i-lucide-trash size-4" />
            {{ t('KANBAN.STAGE_MENU.DELETE_STAGE') }}
          </button>
          <button
            v-if="isAdmin"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-n-ruby-11 hover:bg-n-ruby-2 disabled:cursor-not-allowed disabled:opacity-50"
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
            <select
              v-model="targetBoardId"
              class="mt-1 w-full rounded-md border border-n-weak bg-n-surface-1 px-2 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            >
              <option
                v-for="board in boards"
                :key="board.id"
                :value="board.id"
                :disabled="
                  board.id !== currentBoardId && !canMoveToAnotherBoard
                "
              >
                {{ board.name }}
              </option>
            </select>
          </label>
          <p v-if="!canMoveToAnotherBoard" class="text-xs text-n-slate-10">
            {{ t('KANBAN.STAGE_MENU.MOVE.NONEMPTY_HINT') }}
          </p>
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.STAGE_MENU.MOVE.POSITION') }}
            <select
              v-model="targetPosition"
              class="mt-1 w-full rounded-md border border-n-weak bg-n-surface-1 px-2 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            >
              <option
                v-for="position in positionOptions"
                :key="position"
                :value="position"
              >
                {{ t('KANBAN.STAGE_MENU.MOVE.POSITION_VALUE', { position }) }}
              </option>
            </select>
          </label>
          <button
            type="submit"
            class="w-full rounded-md bg-n-brand px-3 py-2 font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="!targetBoardId || isBusy"
          >
            {{ t('KANBAN.STAGE_MENU.MOVE.SUBMIT') }}
          </button>
        </form>

        <div v-else-if="view === 'moveCards'" class="p-2">
          <p
            v-if="regularStages.length === 0"
            class="px-2 py-3 text-sm text-n-slate-10"
          >
            {{ t('KANBAN.STAGE_MENU.MOVE_CARDS.EMPTY') }}
          </p>
          <button
            v-for="targetStage in regularStages"
            :key="targetStage.id"
            type="button"
            class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy || targetStage.id === stage.id"
            @click="
              emitAction('moveCards', { targetStageId: targetStage.id }, hide)
            "
          >
            <span class="truncate">{{ targetStage.name }}</span>
            <span class="text-xs text-n-slate-10">
              {{
                targetStage.id === stage.id
                  ? t('KANBAN.STAGE_MENU.MOVE_CARDS.CURRENT')
                  : t('KANBAN.STAGE_MENU.MOVE_CARDS.TARGET')
              }}
            </span>
          </button>
        </div>

        <div v-else-if="view === 'sort'" class="p-2">
          <button
            v-for="option in sortOptions"
            :key="option.value"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
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
