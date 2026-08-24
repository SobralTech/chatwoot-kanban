<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Select from 'dashboard/components-next/select/Select.vue';
import { boardAcceptsInbox } from 'dashboard/helper/kanbanBoardScope';

const props = defineProps({
  boards: {
    type: Array,
    default: () => [],
  },
  cards: {
    type: Array,
    default: () => [],
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
  defaultSubject: {
    type: String,
    default: '',
  },
  isLoadingBoards: {
    type: Boolean,
    default: false,
  },
  boardsError: {
    type: String,
    default: '',
  },
  isCreating: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['cancel', 'create', 'open-existing']);
const { t } = useI18n();

const selectedBoardId = ref('');
const selectedStageId = ref('');
const subject = ref('');
const subjectInput = ref(null);

const eligibleBoards = computed(() =>
  props.boards.filter(
    board => board.active !== false && boardAcceptsInbox(board, props.inboxId)
  )
);
const selectedBoard = computed(() =>
  eligibleBoards.value.find(
    board => Number(board.id) === Number(selectedBoardId.value)
  )
);
const boardStages = board =>
  board?.stagesSummary || board?.stages_summary || [];
const regularStages = computed(() => {
  const board = selectedBoard.value;
  if (!board) return [];

  const terminalIds = [board.wonStageId, board.lostStageId]
    .filter(Boolean)
    .map(Number);

  return boardStages(board).filter(
    stage => stage.active !== false && !terminalIds.includes(Number(stage.id))
  );
});
const existingCard = computed(() =>
  props.cards.find(card => {
    const board = card.kanbanBoard || card.kanban_board;
    return (
      Number(board?.id ?? card.kanbanBoardId) === Number(selectedBoardId.value)
    );
  })
);
const boardOptions = computed(() =>
  eligibleBoards.value.map(board => ({ value: board.id, label: board.name }))
);
const stageOptions = computed(() =>
  regularStages.value.map(stage => ({ value: stage.id, label: stage.name }))
);
const canSubmit = computed(
  () =>
    !!selectedBoardId.value &&
    !!selectedStageId.value &&
    !!subject.value.trim() &&
    !props.isCreating
);

const resetBoardSelection = () => {
  if (eligibleBoards.value.length === 1) {
    selectedBoardId.value = eligibleBoards.value[0].id;
  } else if (
    !eligibleBoards.value.some(
      board => Number(board.id) === Number(selectedBoardId.value)
    )
  ) {
    selectedBoardId.value = '';
  }
};

watch(
  eligibleBoards,
  () => {
    resetBoardSelection();
  },
  { immediate: true }
);

watch(
  [selectedBoard, regularStages],
  () => {
    if (
      !regularStages.value.some(
        stage => Number(stage.id) === Number(selectedStageId.value)
      )
    ) {
      selectedStageId.value = regularStages.value[0]?.id || '';
    }
  },
  { immediate: true }
);

const focusSubject = () => {
  nextTick(() => {
    subjectInput.value?.focus();
    subjectInput.value?.select();
  });
};

onMounted(() => {
  subject.value = props.defaultSubject;
  focusSubject();
});

const onBoardChange = () => {
  selectedStageId.value = regularStages.value[0]?.id || '';
};

const submit = () => {
  if (!canSubmit.value) return;

  emit('create', {
    kanban_board_id: Number(selectedBoardId.value),
    kanban_stage_id: Number(selectedStageId.value),
    subject: subject.value.trim(),
  });
};
</script>

<template>
  <form
    data-testid="kanban-conversation-card-form"
    class="mt-3 grid gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
    @submit.prevent="submit"
    @keydown.esc.prevent="emit('cancel')"
  >
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.NEW_OPPORTUNITY') }}
    </h3>

    <p v-if="isLoadingBoards" class="m-0 text-xs text-n-slate-11">
      {{ t('CONVERSATION_SIDEBAR.KANBAN.LOADING') }}
    </p>
    <p v-else-if="boardsError" class="m-0 text-xs text-n-ruby-11">
      {{ boardsError }}
    </p>
    <p
      v-else-if="!eligibleBoards.length"
      data-testid="kanban-conversation-card-no-eligible-boards"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t('CONVERSATION_SIDEBAR.KANBAN.NO_ELIGIBLE_BOARDS') }}
    </p>

    <label
      v-if="eligibleBoards.length"
      class="grid gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
      <Select
        v-model="selectedBoardId"
        data-testid="kanban-conversation-card-board"
        :options="boardOptions"
        :placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD')"
        :disabled="isLoadingBoards || !eligibleBoards.length || isCreating"
        full-width
        class="font-normal"
        @update:model-value="onBoardChange"
      />
    </label>

    <div
      v-if="eligibleBoards.length && existingCard"
      data-testid="kanban-conversation-card-duplicate-warning"
      class="flex items-center gap-2 rounded-md bg-n-amber-2 px-2 py-1.5 text-xs text-n-amber-11"
    >
      <span class="min-w-0 flex-1">
        {{
          t('CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD', {
            id: existingCard.id,
          })
        }}
      </span>
      <button
        type="button"
        class="flex-shrink-0 font-medium underline hover:no-underline"
        @click="emit('open-existing', existingCard)"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.OPEN_EXISTING') }}
      </button>
    </div>

    <label
      v-if="eligibleBoards.length"
      class="grid gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
      <Select
        v-model="selectedStageId"
        data-testid="kanban-conversation-card-stage"
        :options="stageOptions"
        :placeholder="t('CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE')"
        :disabled="!selectedBoard || !regularStages.length || isCreating"
        full-width
        class="font-normal"
      />
      <span
        v-if="selectedBoard && !regularStages.length"
        class="font-normal text-n-slate-10"
      >
        {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
      </span>
    </label>

    <label
      v-if="eligibleBoards.length"
      class="grid gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ t('CONVERSATION_SIDEBAR.KANBAN.SUBJECT') }}
      <input
        ref="subjectInput"
        v-model="subject"
        data-testid="kanban-conversation-card-subject"
        type="text"
        class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm font-normal text-n-slate-12"
        :disabled="isCreating"
      />
    </label>

    <p v-if="eligibleBoards.length && error" class="m-0 text-xs text-n-ruby-11">
      {{ error }}
    </p>

    <div class="flex justify-end gap-2">
      <button
        type="button"
        class="h-8 rounded-md px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="isCreating"
        @click="emit('cancel')"
      >
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CANCEL') }}
      </button>
      <button
        v-if="eligibleBoards.length"
        type="submit"
        data-testid="kanban-conversation-card-create"
        class="h-8 rounded-md bg-n-brand px-3 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="!canSubmit"
      >
        <i
          v-if="isCreating"
          class="i-lucide-loader-circle mr-1 inline-block size-3 animate-spin"
        />
        {{ t('CONVERSATION_SIDEBAR.KANBAN.CREATE') }}
      </button>
    </div>
  </form>
</template>
