<script setup>
import { computed, nextTick, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { format, differenceInCalendarDays } from 'date-fns';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import KanbanCardStatusBadge from './KanbanCardStatusBadge.vue';
import KanbanDueDatePicker from './KanbanDueDatePicker.vue';
import KanbanMenuHeader from './KanbanMenuHeader.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  boards: {
    type: Array,
    default: () => [],
  },
  isSelected: {
    type: Boolean,
    default: false,
  },
  isSelectionMode: {
    type: Boolean,
    default: false,
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
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
  reasons: {
    type: Array,
    default: () => [],
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'openDetails',
  'openConversation',
  'openConversationInNewTab',
  'removeCard',
  'updatePriority',
  'changeStatus',
  'moveToStage',
  'moveToBoard',
  'assignAgent',
  'updateDueDate',
  'updateLabels',
  'toggleSelect',
]);

const { t } = useI18n();
const store = useStore();
const accountLabels = computed(() => store.getters['labels/getLabels'] || []);
const view = ref('root');
const dueDateInput = ref('');
const { isTerminalStage } = useKanbanStageOrder({
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
  lostStageId: toRef(props, 'lostStageId'),
});

const conversation = computed(() => props.card.conversation || {});
const contact = computed(
  () => props.card.contact || conversation.value?.meta?.sender || {}
);
const inbox = computed(
  () =>
    props.card.inbox ||
    store.getters['inboxes/getInboxById'](conversation.value.inboxId)
);

const hasConversation = computed(() => !!props.card.conversationId);
const contactName = computed(
  () => contact.value?.name || t('KANBAN.CARD.UNKNOWN_CONTACT')
);
const priority = computed(
  () => props.card.cardPriority ?? props.card.card_priority ?? ''
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
const inboxName = computed(
  () =>
    inbox.value?.name ||
    conversation.value?.meta?.channel ||
    t('KANBAN.CARD.UNKNOWN_INBOX')
);
const namedInbox = computed(() => ({ ...inbox.value, name: inboxName.value }));
const contactThumbnail = computed(
  () => contact.value?.thumbnail || contact.value?.avatarUrl || ''
);
const assignees = computed(() => props.card.assignees || []);
const primaryAssignee = computed(() => assignees.value[0] || null);
const extraAssigneeCount = computed(() =>
  Math.max(assignees.value.length - 1, 0)
);
const extraAssigneeLabel = computed(() => `+${extraAssigneeCount.value}`);
const moveBoardId = ref(null);
const moveTargetStage = ref(null);
const currentBoardId = computed(() => {
  const boardId = props.board?.id ?? props.card.kanbanBoardId;
  return boardId ? Number(boardId) : null;
});
const sourceBoard = computed(() => {
  if (props.board?.id) return props.board;

  return (
    props.boards.find(board => Number(board.id) === currentBoardId.value) || {}
  );
});
const cardInboxId = computed(() => {
  const inboxId =
    props.card.inboxId ?? props.card.inbox?.id ?? conversation.value.inboxId;
  return inboxId ? Number(inboxId) : null;
});
// The board the card sits on comes from the show endpoint, which sends
// allowedInboxIds; every other board comes from the index, which sends the
// inboxes themselves.
const boardAllowedInboxIds = board =>
  (
    board.allowedInboxIds ??
    board.allowedInboxes?.map(allowedInbox => allowedInbox.id) ??
    []
  ).map(Number);
const boardAcceptsCardInbox = board =>
  board.inboxScopeMode !== 'selected_inboxes' ||
  boardAllowedInboxIds(board).includes(cardInboxId.value);
const movableBoards = computed(() => {
  let availableBoards = props.boards;
  if (!availableBoards.length && props.board?.id) {
    availableBoards = [props.board];
  }
  return availableBoards
    .filter(board => board.active !== false && boardAcceptsCardInbox(board))
    .slice()
    .sort((firstBoard, secondBoard) => {
      const firstIsCurrent = Number(firstBoard.id) === currentBoardId.value;
      const secondIsCurrent = Number(secondBoard.id) === currentBoardId.value;
      if (firstIsCurrent !== secondIsCurrent) return firstIsCurrent ? -1 : 1;

      return (
        Number(firstBoard.position ?? 0) - Number(secondBoard.position ?? 0)
      );
    });
});
const selectedMoveBoard = computed(
  () =>
    movableBoards.value.find(
      board => Number(board.id) === Number(moveBoardId.value)
    ) || sourceBoard.value
);
const moveBoardName = computed(
  () =>
    selectedMoveBoard.value?.name ||
    t('KANBAN.CARD.MOVE_CURRENT_BOARD', { name: '' })
);
const moveBoardOptions = computed(() =>
  movableBoards.value.map(board => ({
    value: board.id,
    label:
      Number(board.id) === currentBoardId.value
        ? t('KANBAN.CARD.MOVE_CURRENT_BOARD', { name: board.name })
        : board.name,
  }))
);
const isCurrentMoveBoard = computed(() => {
  if (!currentBoardId.value) return moveBoardId.value === null;

  return Number(moveBoardId.value) === currentBoardId.value;
});
const moveStages = computed(() => {
  const board = selectedMoveBoard.value;
  const stages = isCurrentMoveBoard.value
    ? props.stages
    : board.stagesSummary || [];
  const wonStageId = isCurrentMoveBoard.value
    ? props.wonStageId
    : board.wonStageId;
  const lostStageId = isCurrentMoveBoard.value
    ? props.lostStageId
    : board.lostStageId;
  const terminalStageIds = [wonStageId, lostStageId]
    .filter(Boolean)
    .map(Number);

  return stages.filter(stage => {
    if (stage.active === false) return false;
    if (terminalStageIds.includes(Number(stage.id))) return false;
    return (
      !isCurrentMoveBoard.value ||
      Number(stage.id) !== Number(props.card.kanbanStageId)
    );
  });
});
const sourceCustomFields = computed(() => sourceBoard.value.customFields || []);
const targetCustomFields = computed(
  () => selectedMoveBoard.value.customFields || []
);
const cardCustomFieldKeys = computed(() =>
  (props.card.customFieldKeys || []).filter(Boolean)
);
const droppedFieldKeys = computed(() =>
  cardCustomFieldKeys.value.filter(key => {
    const sourceField = sourceCustomFields.value.find(
      field => field.key === key
    );
    if (!sourceField) return true;

    return !targetCustomFields.value.some(
      targetField =>
        targetField.key === key &&
        targetField.fieldType === sourceField.fieldType &&
        Boolean(targetField.multiple) === Boolean(sourceField.multiple)
    );
  })
);
const moveConsequences = computed(() => {
  const sourceStageId = Number(props.card.kanbanStageId);
  const sourceWonStageId = Number(sourceBoard.value.wonStageId);
  const sourceLostStageId = Number(sourceBoard.value.lostStageId);
  const consequences = [];

  if ([sourceWonStageId, sourceLostStageId].includes(sourceStageId)) {
    consequences.push({ key: 'MOVE_CONFIRM_REOPEN', params: {} });
  }

  const reasonId = Number(props.card.kanbanReasonId);
  if (reasonId) {
    const reason = props.reasons.find(item => Number(item.id) === reasonId);
    consequences.push({
      key: 'MOVE_CONFIRM_REASON',
      params: { reason: reason?.title || reasonId },
    });
  }

  if (droppedFieldKeys.value.length) {
    consequences.push({
      key: 'MOVE_CONFIRM_FIELDS',
      params: {
        count: droppedFieldKeys.value.length,
        total: cardCustomFieldKeys.value.length,
        board: moveBoardName.value,
        keys: droppedFieldKeys.value.join(', '),
      },
    });
  }

  const isTerminal = [sourceWonStageId, sourceLostStageId].includes(
    sourceStageId
  );
  const { wonRecurrenceEnabled, lostRecurrenceEnabled } = sourceBoard.value;
  const recurrenceEnabledForSourceStage =
    (sourceStageId === sourceWonStageId && Boolean(wonRecurrenceEnabled)) ||
    (sourceStageId === sourceLostStageId && Boolean(lostRecurrenceEnabled));

  if (isTerminal && recurrenceEnabledForSourceStage) {
    consequences.push({
      key: 'MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES',
      params: { board: sourceBoard.value.name },
    });
  } else if (!isTerminal && (wonRecurrenceEnabled || lostRecurrenceEnabled)) {
    consequences.push({
      key: 'MOVE_CONFIRM_RECURRENCE_MAY_RECREATE',
      params: { board: sourceBoard.value.name },
    });
  }

  return consequences;
});
const viewTitle = computed(() => {
  switch (view.value) {
    case 'move':
      return t('KANBAN.CARD.MOVE_TO');
    case 'move-confirm':
      return t('KANBAN.CARD.MOVE_CONFIRM_TITLE', {
        board: moveBoardName.value,
      });
    case 'assign':
      return t('KANBAN.CARD.ASSIGN_TO');
    case 'priority':
      return t('KANBAN.CARD.CHANGE_PRIORITY');
    case 'due':
      return t('KANBAN.CARD.DUE_DATE');
    case 'labels':
      return t('CONTACT_PANEL.LABELS.LABEL_SELECT.TITLE');
    default:
      return t('KANBAN.CARD.ACTIONS_MENU');
  }
});
const subject = computed(() => props.card.subject || '');
const labels = computed(() => {
  const cardLabels = props.card.labels || props.card.label_list || [];

  return cardLabels.map(label => {
    if (typeof label !== 'string') return label;

    return (
      accountLabels.value.find(
        accountLabel => accountLabel.title === label
      ) || {
        title: label,
      }
    );
  });
});
const cardLabelTitles = computed(() =>
  labels.value.map(label => label.title).filter(Boolean)
);

const toUnixTimestamp = value => {
  if (!value) return null;
  if (typeof value === 'number') return value;

  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? null : Math.floor(timestamp / 1000);
};

const stageEnteredAt = computed(() =>
  toUnixTimestamp(props.card.stage_entered_at || props.card.stageEnteredAt)
);
const stageTime = computed(() =>
  stageEnteredAt.value
    ? shortTimestamp(dynamicTime(stageEnteredAt.value), true)
    : ''
);
const dueAt = computed(() => props.card.due_at || props.card.dueAt);
const dueAtDate = computed(() => {
  if (!dueAt.value) return null;

  const dueDate = new Date(dueAt.value);
  return Number.isNaN(dueDate.getTime()) ? null : dueDate;
});
const dueAtLabel = computed(() =>
  dueAtDate.value ? format(dueAtDate.value, 'dd/MM/yyyy') : ''
);
const dueAtStatus = computed(() => {
  if (!dueAtDate.value) return '';

  const diffInDays = differenceInCalendarDays(dueAtDate.value, new Date());
  if (diffInDays <= 0) return 'today';
  if (diffInDays === 1) return 'tomorrow';
  return 'upcoming';
});
const dueAtClasses = computed(() => {
  switch (dueAtStatus.value) {
    case 'today':
      return 'bg-n-ruby-3 text-n-ruby-11';
    case 'tomorrow':
      return 'bg-n-amber-3 text-n-amber-11';
    default:
      return 'bg-n-teal-3 text-n-teal-11';
  }
});

const cardValue = computed(() => Number(props.card.value) || 0);
const formattedCardValue = computed(() => formatCurrency(cardValue.value));

const openDetails = () => {
  emit('openDetails', props.card);
};

const resetView = () => {
  view.value = 'root';
  moveBoardId.value = null;
  moveTargetStage.value = null;
};

const closeMenu = hide => {
  resetView();
  hide?.();
};

const openView = nextView => {
  if (nextView === 'due') dueDateInput.value = formatDateInput(dueAt.value);
  if (nextView === 'move') {
    moveBoardId.value = currentBoardId.value;
    moveTargetStage.value = null;
  }
  view.value = nextView;
};

const goBack = () => {
  view.value = view.value === 'move-confirm' ? 'move' : 'root';
};

const onSelectDueDate = (value, hide) => {
  emit('updateDueDate', props.card, value);
  closeMenu(hide);
};

const onSelectPriority = (option, hide) => {
  emit('updatePriority', props.card, option.value);
  closeMenu(hide);
};

const onMoveToStage = (stage, hide) => {
  if (isCurrentMoveBoard.value) {
    emit('moveToStage', props.card, stage.id);
    closeMenu(hide);
    return;
  }

  moveTargetStage.value = stage;
  view.value = 'move-confirm';
};

const onConfirmMoveToBoard = hide => {
  if (!moveTargetStage.value || !moveBoardId.value) return;

  emit('moveToBoard', props.card, {
    boardId: Number(moveBoardId.value),
    stageId: moveTargetStage.value.id,
  });
  closeMenu(hide);
};

const onAssignAgent = (user, hide) => {
  emit('assignAgent', props.card, user.id);
  closeMenu(hide);
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || cardLabelTitles.value.includes(title)) return;

  emit('updateLabels', props.card, [...cardLabelTitles.value, title]);
};

const onRemoveLabel = title => {
  emit(
    'updateLabels',
    props.card,
    cardLabelTitles.value.filter(labelTitle => labelTitle !== title)
  );
};

const openConversationFromMenu = hide => {
  emit('openConversation', props.card, {});
  closeMenu(hide);
};

const openConversationInNewTab = hide => {
  emit('openConversationInNewTab', props.card);
  closeMenu(hide);
};

const removeCard = hide => {
  emit('removeCard', props.card);
  closeMenu(hide);
};

const onChangeStatus = payload => {
  emit('changeStatus', props.card, payload);
};

const openCard = event => {
  event.currentTarget?.focus?.();
  if (hasConversation.value) {
    emit('openConversation', props.card, event);
    return;
  }

  emit('openDetails', props.card);
};

const toggleSelection = async event => {
  const checkbox = event.target;
  emit('toggleSelect', props.card, event);

  // The board can refuse the toggle once the selection cap is reached, and the browser
  // has already flipped the box by then, so re-assert whatever the board decided.
  await nextTick();
  checkbox.checked = props.isSelected;
};
</script>

<template>
  <article
    tabindex="0"
    class="card-drag-handle group relative cursor-pointer select-none rounded-lg border border-n-weak bg-n-surface-1 p-3 transition-colors hover:border-n-brand"
    :class="{ 'border-n-brand ring-1 ring-n-brand': isSelected }"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    @click="openCard"
  >
    <label
      class="no-drag absolute top-1.5 z-10 flex size-7 items-center justify-center rounded-md bg-n-surface-1 shadow-sm opacity-0 transition-opacity group-hover:opacity-100 ltr:right-11 rtl:left-11"
      :class="{ 'opacity-100': isSelectionMode || isSelected }"
      @click.stop
    >
      <input
        type="checkbox"
        class="no-drag size-4 cursor-pointer accent-n-brand"
        :checked="isSelected"
        :aria-label="t('KANBAN.BULK.SELECT_CARD')"
        @click.stop="toggleSelection"
      />
    </label>
    <span
      class="no-drag absolute top-1.5 inline-flex ltr:right-1.5 rtl:left-1.5"
      @click.stop
    >
      <Popover align="end" disable-mobile-view @hide="resetView">
        <button
          type="button"
          data-testid="kanban-card-actions"
          class="no-drag flex size-8 items-center justify-center rounded-md border border-n-weak bg-n-surface-1 text-n-slate-11 opacity-0 shadow-sm transition-opacity hover:bg-n-alpha-2 focus:opacity-100 focus:outline-none focus:ring-1 focus:ring-n-brand group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
          :aria-label="t('KANBAN.CARD.ACTIONS_MENU')"
          :title="t('KANBAN.CARD.ACTIONS_MENU')"
          :disabled="isBusy"
        >
          <i v-if="isBusy" class="i-lucide-loader-circle size-4 animate-spin" />
          <i v-else class="i-lucide-more-vertical size-5" />
        </button>

        <template #content="{ hide }">
          <div
            data-testid="kanban-card-actions-menu"
            class="w-72 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl text-sm text-n-slate-12"
          >
            <KanbanMenuHeader
              :title="viewTitle"
              :show-back="view !== 'root'"
              @back="goBack"
              @close="closeMenu(hide)"
            />

            <div v-if="view === 'root'" class="p-1">
              <button
                v-if="hasConversation"
                type="button"
                data-testid="kanban-card-open-conversation"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openConversationFromMenu(hide)"
              >
                <i class="i-lucide-message-square size-4" />
                {{ t('KANBAN.CARD.OPEN_CONVERSATION', { contactName }) }}
              </button>
              <button
                v-if="hasConversation"
                type="button"
                data-testid="kanban-card-open-new-tab"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openConversationInNewTab(hide)"
              >
                <i class="i-lucide-external-link size-4" />
                {{ t('KANBAN.CARD.OPEN_IN_NEW_TAB') }}
              </button>
              <button
                type="button"
                data-testid="kanban-card-edit"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="
                  closeMenu(hide);
                  openDetails();
                "
              >
                <i class="i-lucide-pencil size-4" />
                {{ t('KANBAN.CARD.EDIT') }}
              </button>
              <button
                type="button"
                data-testid="kanban-card-move"
                class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openView('move')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-corner-up-right size-4" />
                  <span class="truncate">{{ t('KANBAN.CARD.MOVE_TO') }}</span>
                </span>
                <i class="i-lucide-chevron-right size-4 flex-shrink-0" />
              </button>
              <button
                type="button"
                data-testid="kanban-card-labels"
                class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openView('labels')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-tags size-4" />
                  <span class="truncate">
                    {{ t('CONTACT_PANEL.LABELS.LABEL_SELECT.TITLE') }}
                  </span>
                </span>
                <span class="flex flex-shrink-0 items-center gap-1">
                  <span
                    v-if="cardLabelTitles.length"
                    class="text-xs text-n-slate-11"
                  >
                    {{ cardLabelTitles.length }}
                  </span>
                  <i class="i-lucide-chevron-right size-4" />
                </span>
              </button>
              <button
                type="button"
                data-testid="kanban-card-assign"
                class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openView('assign')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-user-round size-4" />
                  <span class="truncate">{{ t('KANBAN.CARD.ASSIGN_TO') }}</span>
                </span>
                <i class="i-lucide-chevron-right size-4 flex-shrink-0" />
              </button>
              <button
                type="button"
                data-testid="kanban-card-priority"
                class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openView('priority')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-signal size-4" />
                  <span class="truncate">{{
                    t('KANBAN.CARD.CHANGE_PRIORITY')
                  }}</span>
                </span>
                <i class="i-lucide-chevron-right size-4 flex-shrink-0" />
              </button>
              <button
                type="button"
                data-testid="kanban-card-due-date"
                class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="openView('due')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-calendar size-4" />
                  <span class="truncate">{{ t('KANBAN.CARD.DUE_DATE') }}</span>
                </span>
                <span class="flex flex-shrink-0 items-center gap-1">
                  <span v-if="dueAtLabel" class="text-xs text-n-slate-11">
                    {{ dueAtLabel }}
                  </span>
                  <i class="i-lucide-chevron-right size-4" />
                </span>
              </button>
              <div class="my-1 border-t border-n-weak" />
              <button
                type="button"
                data-testid="kanban-card-remove"
                :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
                :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-n-ruby-11 hover:bg-n-ruby-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="removeCard(hide)"
              >
                <i class="i-lucide-trash size-4" />
                {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
              </button>
            </div>

            <div v-else-if="view === 'move'" class="p-1">
              <label
                v-if="moveBoardOptions.length"
                class="block px-3 py-2 text-xs font-medium text-n-slate-11"
              >
                {{ t('KANBAN.CARD.MOVE_BOARD_LABEL') }}
                <Select
                  v-model="moveBoardId"
                  data-testid="kanban-card-move-board"
                  :options="moveBoardOptions"
                  full-width
                  class="mt-1 font-normal"
                />
              </label>
              <div
                v-if="moveBoardOptions.length"
                class="mx-2 border-t border-n-weak"
              />
              <p
                v-if="!moveStages.length"
                class="px-3 py-2 text-sm text-n-slate-10"
              >
                {{
                  isCurrentMoveBoard &&
                  isTerminalStage({ id: card.kanbanStageId })
                    ? t('KANBAN.CARD.TERMINAL_STAGE_HINT')
                    : t('KANBAN.CARD.NO_REGULAR_STAGES')
                }}
              </p>
              <button
                v-for="stage in moveStages"
                :key="stage.id"
                type="button"
                data-testid="kanban-card-move-stage"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="onMoveToStage(stage, hide)"
              >
                <span
                  class="size-2.5 flex-shrink-0 rounded-full"
                  :style="{ backgroundColor: stage.color }"
                />
                <span class="min-w-0 truncate">{{ stage.name }}</span>
              </button>
            </div>

            <div v-else-if="view === 'move-confirm'" class="p-3">
              <p
                data-testid="kanban-card-move-confirm-stage"
                class="font-medium text-n-slate-12"
              >
                {{ moveTargetStage?.name }}
              </p>
              <ul
                v-if="moveConsequences.length"
                data-testid="kanban-card-move-consequences"
                class="mt-3 list-disc space-y-2 pl-4 text-sm text-n-slate-11"
              >
                <li
                  v-for="consequence in moveConsequences"
                  :key="consequence.key"
                >
                  {{ t(`KANBAN.CARD.${consequence.key}`, consequence.params) }}
                </li>
              </ul>
              <p
                v-else
                data-testid="kanban-card-move-confirm-clean"
                class="mt-3 text-sm text-n-slate-11"
              >
                {{ t('KANBAN.CARD.MOVE_CONFIRM_CLEAN') }}
              </p>
              <div class="mt-4 flex justify-end gap-2">
                <button
                  type="button"
                  data-testid="kanban-card-move-confirm-cancel"
                  class="rounded-md px-3 py-2 text-sm hover:bg-n-alpha-2"
                  @click="view = 'move'"
                >
                  {{ t('KANBAN.CARD.MOVE_CONFIRM_CANCEL') }}
                </button>
                <button
                  type="button"
                  data-testid="kanban-card-move-confirm-submit"
                  class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isBusy"
                  @click="onConfirmMoveToBoard(hide)"
                >
                  {{ t('KANBAN.CARD.MOVE_CONFIRM_SUBMIT') }}
                </button>
              </div>
            </div>

            <div v-else-if="view === 'assign'" class="p-1">
              <p
                v-if="!assignableUsers.length"
                class="px-3 py-2 text-sm text-n-slate-10"
              >
                {{ t('KANBAN.CARD.NO_ASSIGNABLE_USERS') }}
              </p>
              <button
                v-for="user in assignableUsers"
                :key="user.id"
                type="button"
                data-testid="kanban-card-assign-agent"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="onAssignAgent(user, hide)"
              >
                <span class="min-w-0 flex-1 truncate">
                  {{ user.name || user.email }}
                </span>
                <i
                  v-if="assignees.some(assignee => assignee.id === user.id)"
                  class="i-lucide-check size-4 flex-shrink-0 text-n-brand"
                />
              </button>
            </div>

            <div v-else-if="view === 'priority'" class="p-1">
              <button
                v-for="option in priorityOptions"
                :key="option.value"
                type="button"
                data-testid="kanban-card-priority-option"
                :data-selected="option.value === priority"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="isBusy"
                @click="onSelectPriority(option, hide)"
              >
                <CardPriorityIcon
                  :priority="option.value"
                  show-empty
                  class="size-3.5 flex-shrink-0"
                />
                <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
                <i
                  v-if="option.value === priority"
                  class="i-lucide-check size-3.5 flex-shrink-0 text-n-brand"
                />
              </button>
            </div>

            <div v-else-if="view === 'due'" class="p-3">
              <KanbanDueDatePicker
                v-model="dueDateInput"
                data-testid="kanban-card-due-date-picker"
                :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
                :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
                @change="onSelectDueDate($event, hide)"
              />
            </div>

            <div v-else-if="view === 'labels'" class="p-2">
              <LabelDropdown
                :account-labels="accountLabels"
                :selected-labels="cardLabelTitles"
                :allow-creation="isAdmin"
                @add="onAddLabel"
                @remove="onRemoveLabel"
              />
            </div>
          </div>
        </template>
      </Popover>
    </span>

    <div class="min-w-0 text-left">
      <p
        v-if="subject"
        class="truncate text-sm font-semibold leading-4 text-n-slate-12"
        :title="subject"
      >
        {{ subject }}
      </p>

      <div v-if="labels.length" class="mt-1 flex flex-wrap gap-1">
        <WootLabel
          v-for="label in labels"
          :key="label.title"
          :title="label.title"
          :bg-color="label.color"
          small
          class="!m-0 max-w-full"
        />
      </div>

      <div class="mt-1 flex items-center gap-1.5">
        <span
          data-testid="kanban-card-contact-avatar"
          class="relative flex flex-shrink-0 rounded-full"
          :title="contactName"
        >
          <Avatar
            :name="contactName"
            :src="contactThumbnail"
            :size="28"
            rounded-full
          />
          <span
            v-if="inbox"
            class="absolute -bottom-1 -right-1 flex size-5 items-center justify-center rounded-full border border-n-surface-1 bg-n-surface-1"
          >
            <ChannelIcon :inbox="inbox" class="size-3.5 text-n-slate-11" />
          </span>
        </span>

        <h4
          class="min-w-0 flex-1 truncate text-xs font-medium leading-4 text-n-slate-12"
        >
          {{ contactName }}
        </h4>

        <span
          v-if="primaryAssignee"
          class="relative flex flex-shrink-0 items-center"
        >
          <Avatar
            :name="primaryAssignee.name"
            :src="primaryAssignee.avatarUrl"
            :size="18"
            rounded-full
          />
          <span
            v-if="extraAssigneeCount"
            class="absolute -bottom-1 -right-1 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-n-slate-9 px-0.5 text-[9px] font-medium leading-none text-white"
          >
            {{ extraAssigneeLabel }}
          </span>
        </span>
      </div>

      <div class="mt-1 flex min-w-0">
        <div
          class="inline-flex max-w-full items-center rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xs leading-4"
        >
          <InboxName
            :inbox="namedInbox"
            :show-icon="false"
            class="max-w-full"
          />
        </div>
      </div>

      <div
        data-testid="kanban-card-meta"
        class="mt-1 flex items-center justify-between gap-1.5 text-xs leading-4 text-n-slate-10"
      >
        <span
          class="no-drag inline-flex flex-shrink-0"
          :title="t('KANBAN.CARD.CHANGE_PRIORITY')"
          @click.stop
        >
          <CardPriorityIcon :priority="priority" show-empty class="!size-3.5" />
        </span>

        <span class="no-drag inline-flex flex-shrink-0" @click.stop>
          <KanbanCardStatusBadge
            :kanban-stage-id="card.kanbanStageId"
            :won-stage-id="wonStageId"
            :lost-stage-id="lostStageId"
            :reasons="reasons"
            :lost-reason-required="lostReasonRequired"
            :disabled="isBusy"
            @change="onChangeStatus"
          />
        </span>

        <div class="flex min-w-0 items-center justify-end gap-1.5">
          <span
            v-if="cardValue > 0"
            data-testid="kanban-card-value"
            class="inline-flex flex-shrink-0 items-center truncate font-medium text-n-slate-11"
          >
            {{ formattedCardValue }}
          </span>
          <span
            v-if="dueAtLabel"
            class="inline-flex flex-shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5"
            :class="dueAtClasses"
            :title="dueAt"
          >
            <i class="i-lucide-calendar size-3" />
            {{ dueAtLabel }}
          </span>
          <span
            v-if="stageTime"
            class="inline-flex min-w-0 items-center gap-1 truncate"
            :title="dynamicTime(stageEnteredAt)"
          >
            <i class="i-lucide-clock size-3 flex-shrink-0" />
            <span class="truncate">{{ stageTime }}</span>
          </span>
        </div>
      </div>
    </div>
  </article>
</template>
