<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';
import KanbanBulkActionMenu from './KanbanBulkActionMenu.vue';
import KanbanReasonPicker from './KanbanReasonPicker.vue';
import {
  BULK_ACTION_BUTTON_CLASSES,
  BULK_ACTION_MENU_CLASSES,
} from './bulkActionClasses';

const props = defineProps({
  selectedCount: {
    type: Number,
    required: true,
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  boards: {
    type: Array,
    default: () => [],
  },
  stages: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
  hasAssignedSelectedCards: {
    type: Boolean,
    default: false,
  },
  hasLabeledSelectedCards: {
    type: Boolean,
    default: false,
  },
  labels: {
    type: Array,
    default: () => [],
  },
  reasons: {
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
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['action', 'clear', 'delete']);
const { t } = useI18n();
const selectedReasonId = ref('');
const moveBoardId = ref(null);

const chooseAction = (action, payload, hide) => {
  emit('action', { action, payload });
  hide?.();
};

const currentBoardId = computed(() =>
  props.board?.id ? Number(props.board.id) : null
);
const sourceBoard = computed(() =>
  props.board?.id
    ? props.board
    : props.boards.find(board => Number(board.id) === currentBoardId.value) ||
      {}
);
const moveBoards = computed(() => {
  let boards = props.boards;
  if (!boards.length && props.board?.id) boards = [sourceBoard.value];

  return boards.filter(board => board?.active !== false);
});
const moveBoardOptions = computed(() =>
  moveBoards.value.map(board => ({
    value: board.id,
    label:
      Number(board.id) === currentBoardId.value
        ? t('KANBAN.CARD.MOVE_CURRENT_BOARD', { name: board.name })
        : board.name,
  }))
);
const selectedMoveBoard = computed(
  () =>
    moveBoards.value.find(
      board => Number(board.id) === Number(moveBoardId.value)
    ) || sourceBoard.value
);
const isCurrentMoveBoard = computed(() => {
  if (moveBoardId.value === null || !currentBoardId.value) return true;

  return Number(moveBoardId.value) === currentBoardId.value;
});
const moveStages = computed(() => {
  const board = selectedMoveBoard.value;
  const stages = isCurrentMoveBoard.value
    ? props.stages
    : board?.stagesSummary || [];
  const terminalStageIds = [
    isCurrentMoveBoard.value ? props.wonStageId : board?.wonStageId,
    isCurrentMoveBoard.value ? props.lostStageId : board?.lostStageId,
  ]
    .filter(Boolean)
    .map(Number);

  return stages.filter(
    stage =>
      stage.active !== false && !terminalStageIds.includes(Number(stage.id))
  );
});

const openMove = () => {
  moveBoardId.value = currentBoardId.value;
};

const chooseMoveStage = (stage, hide) => {
  const payload = { kanban_stage_id: stage.id };
  if (!isCurrentMoveBoard.value) {
    payload.target_kanban_board_id = Number(moveBoardId.value);
  }

  chooseAction('move', payload, hide);
};

const resetMove = () => {
  moveBoardId.value = null;
};

const assigneeOptions = computed(() =>
  props.assignableUsers.map(user => ({
    value: user.id,
    label: user.name || user.email,
    avatarUrl: user.avatarUrl,
  }))
);

const labelOptions = computed(() =>
  props.labels.map(label => ({
    value: label.title,
    label: label.title,
    color: label.color,
  }))
);

const priorityOptions = computed(() => [
  { value: '', label: t('CONVERSATION.PRIORITY.OPTIONS.NONE') },
  {
    value: CONVERSATION_PRIORITY.URGENT,
    label: t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
  },
  {
    value: CONVERSATION_PRIORITY.HIGH,
    label: t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
  },
  {
    value: CONVERSATION_PRIORITY.MEDIUM,
    label: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
  },
  {
    value: CONVERSATION_PRIORITY.LOW,
    label: t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
  },
]);

const chooseReason = hide => {
  if (props.lostReasonRequired && !selectedReasonId.value) return;

  chooseAction(
    'lose',
    { kanban_reason_id: selectedReasonId.value || null },
    hide
  );
  selectedReasonId.value = '';
};

const resetReason = () => {
  selectedReasonId.value = '';
};
</script>

<template>
  <div
    v-show="selectedCount"
    data-testid="kanban-bulk-actions"
    class="fixed bottom-4 left-1/2 z-30 flex max-w-[calc(100vw-2rem)] -translate-x-1/2 flex-nowrap items-center gap-1 overflow-x-auto rounded-xl border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur [&::-webkit-scrollbar]:hidden"
  >
    <div
      class="inline-flex flex-shrink-0 items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-1.5"
    >
      <span
        data-testid="kanban-bulk-selected-count"
        class="text-xs font-semibold text-n-slate-12"
      >
        {{ t('KANBAN.BULK.SELECTED', { count: selectedCount }) }}
      </span>

      <button
        type="button"
        data-testid="kanban-bulk-clear"
        class="flex size-5 items-center justify-center rounded-full bg-n-alpha-3 p-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('KANBAN.BULK.CLEAR')"
        :title="t('KANBAN.BULK.CLEAR')"
        @click="emit('clear')"
      >
        <i class="i-lucide-x size-3.5 leading-none" />
      </button>
    </div>

    <Popover align="start" disable-mobile-view @hide="resetMove">
      <button
        type="button"
        data-testid="kanban-bulk-action-move"
        :class="BULK_ACTION_BUTTON_CLASSES"
        :disabled="isBusy"
        @click="openMove"
      >
        <i class="i-lucide-corner-up-right size-4" />
        {{ t('KANBAN.BULK.MOVE') }}
      </button>
      <template #content="{ hide }">
        <div :class="BULK_ACTION_MENU_CLASSES">
          <label class="block text-xs font-medium text-n-slate-11">
            {{ t('KANBAN.CARD.MOVE_BOARD_LABEL') }}
            <Select
              v-model="moveBoardId"
              data-testid="kanban-bulk-move-board"
              :options="moveBoardOptions"
              full-width
              class="mt-1 font-normal"
            />
          </label>
          <div class="my-2 border-t border-n-weak" />
          <p
            v-if="!moveStages.length"
            class="px-2 py-2 text-sm text-n-slate-10"
          >
            {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
          </p>
          <button
            v-for="stage in moveStages"
            :key="stage.id"
            type="button"
            data-testid="kanban-bulk-move-stage"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isBusy"
            @click="chooseMoveStage(stage, hide)"
          >
            <span
              class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9"
              :style="{ backgroundColor: stage.color }"
            />
            <span class="min-w-0 flex-1 truncate">{{ stage.name }}</span>
          </button>
        </div>
      </template>
    </Popover>

    <KanbanBulkActionMenu
      :label="t('KANBAN.BULK.ASSIGN')"
      icon="i-lucide-user-round"
      :options="assigneeOptions"
      :empty-text="t('KANBAN.CARD.NO_ASSIGNABLE_USERS')"
      trigger-testid="kanban-bulk-action-assign"
      option-testid="kanban-bulk-assign-agent"
      multiple
      :apply-label="t('KANBAN.BULK.APPLY')"
      apply-icon="i-lucide-user-round-plus"
      apply-testid="kanban-bulk-assign-submit"
      :is-busy="isBusy"
      @apply="chooseAction('assign', { assignee_ids: $event })"
    >
      <template #optionContent="{ option }">
        <Avatar
          :name="option.label"
          :src="option.avatarUrl"
          :size="20"
          rounded-full
        />
        <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
      </template>
      <template #footer="{ hide }">
        <button
          v-if="hasAssignedSelectedCards"
          type="button"
          data-testid="kanban-bulk-unassign"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-11 hover:bg-n-alpha-2"
          :disabled="isBusy"
          @click="chooseAction('assign', { assignee_ids: [] }, hide)"
        >
          <i class="i-lucide-user-round-x size-4" />
          {{ t('KANBAN.BULK.UNASSIGN') }}
        </button>
      </template>
    </KanbanBulkActionMenu>

    <KanbanBulkActionMenu
      :label="t('KANBAN.BULK.LABEL')"
      icon="i-lucide-tag"
      :options="labelOptions"
      :empty-text="t('KANBAN.BULK.NO_LABELS')"
      trigger-testid="kanban-bulk-action-label"
      option-testid="kanban-bulk-label-option"
      menu-class="!w-fit"
      multiple
      :apply-label="t('KANBAN.BULK.APPLY')"
      apply-icon="i-lucide-tags"
      apply-testid="kanban-bulk-label-submit"
      :is-busy="isBusy"
      @apply="chooseAction('label', { labels: $event })"
    >
      <template #optionContent="{ option }">
        <WootLabel
          :title="option.label"
          :bg-color="option.color"
          small
          class="!m-0 max-w-full flex-1"
        />
      </template>
      <template #footer="{ hide }">
        <button
          v-if="hasLabeledSelectedCards"
          type="button"
          data-testid="kanban-bulk-remove-labels"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-11 hover:bg-n-alpha-2"
          :disabled="isBusy"
          @click="chooseAction('clear_labels', {}, hide)"
        >
          <i class="i-lucide-tags size-4" />
          {{ t('KANBAN.BULK.REMOVE_ALL_LABELS') }}
        </button>
      </template>
    </KanbanBulkActionMenu>

    <KanbanBulkActionMenu
      :label="t('KANBAN.BULK.PRIORITY')"
      icon="i-lucide-signal"
      :options="priorityOptions"
      trigger-testid="kanban-bulk-action-priority"
      option-testid="kanban-bulk-priority-option"
      :is-busy="isBusy"
      @select="chooseAction('priority', { priority: $event || null })"
    >
      <template #optionIcon="{ option }">
        <CardPriorityIcon :priority="option.value" show-empty class="size-4" />
      </template>
    </KanbanBulkActionMenu>

    <!-- The only menu whose body is a form rather than a list of options. -->
    <Popover align="start" disable-mobile-view @hide="resetReason">
      <button
        type="button"
        data-testid="kanban-bulk-action-lose"
        :class="BULK_ACTION_BUTTON_CLASSES"
        :disabled="isBusy"
      >
        <i class="i-lucide-x-circle size-4 text-n-ruby-11" />
        {{ t('KANBAN.BULK.LOSE') }}
      </button>
      <template #content="{ hide }">
        <div :class="BULK_ACTION_MENU_CLASSES">
          <KanbanReasonPicker
            v-model="selectedReasonId"
            :reasons="reasons"
            reason-type="lost"
            :required="lostReasonRequired"
            testid="kanban-bulk-loss-reason"
          />
          <button
            type="button"
            data-testid="kanban-bulk-confirm-lose"
            class="mt-2 w-full rounded-md bg-n-ruby-9 px-3 py-1.5 text-xs font-medium text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="lostReasonRequired && !selectedReasonId"
            @click="chooseReason(hide)"
          >
            {{ t('KANBAN.CARD.STATUS.CONFIRM') }}
          </button>
        </div>
      </template>
    </Popover>

    <button
      type="button"
      data-testid="kanban-bulk-action-delete"
      :class="`${BULK_ACTION_BUTTON_CLASSES} text-n-ruby-11 hover:bg-n-ruby-2`"
      :disabled="isBusy"
      @click="emit('delete')"
    >
      <i class="i-lucide-trash size-4" />
      {{ t('KANBAN.BULK.DELETE') }}
    </button>
  </div>
</template>
