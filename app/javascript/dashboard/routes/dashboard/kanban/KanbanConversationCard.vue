<script setup>
import { computed, nextTick, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useKanbanMoveTarget } from 'dashboard/composables/useKanbanMoveTarget';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';
import { SLA_STALE } from 'dashboard/helper/kanbanStageSla';
import { getKanbanMoveConsequences } from 'dashboard/helper/kanbanMoveConsequences';
import { CARD_STATUS_TYPES } from 'dashboard/helper/kanbanCardStatus';
import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';
import { useKanbanCardStatusActions } from 'dashboard/composables/useKanbanCardStatusActions';
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
import KanbanDueDateBadge from './KanbanDueDateBadge.vue';
import KanbanDueDatePicker from './KanbanDueDatePicker.vue';
import KanbanMenuHeader from './KanbanMenuHeader.vue';
import KanbanStatusMenuItems from './KanbanStatusMenuItems.vue';
import KanbanStatusReasonForm from './KanbanStatusReasonForm.vue';
import {
  MENU_DIVIDER_CLASSES,
  MENU_OPTION_CLASSES,
  MENU_OPTION_DESTRUCTIVE_CLASSES,
} from './menuClasses';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  // Also decides `.no-drag` on the root: Sortable's filter covers that class, so a card
  // with an action in flight refuses the drag on its own now that a busy card no longer
  // freezes the drag handles of every column on the board.
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
  slaHours: {
    type: [Number, String],
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
  variant: {
    type: String,
    default: 'board',
    validator: value => ['board', 'list'].includes(value),
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
const actionsPopover = ref(null);
const { isTerminalStage } = useKanbanStageOrder({
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
  lostStageId: toRef(props, 'lostStageId'),
});
const { hasTerminals, isOpen, canSkipReason, statusPayloadFor } =
  useKanbanCardStatusActions({
    stageId: computed(() => props.card.kanbanStageId),
    wonStageId: toRef(props, 'wonStageId'),
    lostStageId: toRef(props, 'lostStageId'),
    reasons: toRef(props, 'reasons'),
    lostReasonRequired: toRef(props, 'lostReasonRequired'),
  });
const isStatusView = computed(() => CARD_STATUS_TYPES.includes(view.value));

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
const visibleAssignees = computed(() => assignees.value.slice(0, 3));
const extraAssigneeCount = computed(() =>
  Math.max(assignees.value.length - visibleAssignees.value.length, 0)
);
const extraAssigneeLabel = computed(() => `+${extraAssigneeCount.value}`);
const moveTargetStage = ref(null);
const currentBoardId = computed(() => {
  const boardId = props.board?.id ?? props.card.kanbanBoardId;
  return boardId ? Number(boardId) : null;
});
const cardInboxId = computed(() => {
  const inboxId =
    props.card.inboxId ?? props.card.inbox?.id ?? conversation.value.inboxId;
  return inboxId ? Number(inboxId) : null;
});
const {
  boardId: moveBoardId,
  boardOptions: moveBoardOptions,
  isCurrentBoard: isCurrentMoveBoard,
  reset: resetMoveTarget,
  selectedBoard: selectedMoveBoard,
  sourceBoard,
  targetStages: moveStages,
} = useKanbanMoveTarget({
  board: toRef(props, 'board'),
  boards: toRef(props, 'boards'),
  currentBoardId,
  excludeStageId: computed(() => props.card.kanbanStageId),
  inboxId: cardInboxId,
  lostStageId: toRef(props, 'lostStageId'),
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
});
const moveBoardName = computed(
  () =>
    selectedMoveBoard.value?.name ||
    t('KANBAN.CARD.MOVE_CURRENT_BOARD', { name: '' })
);
const moveConsequences = computed(() => {
  return getKanbanMoveConsequences({
    card: props.card,
    sourceBoard: sourceBoard.value,
    targetBoard: selectedMoveBoard.value,
    reasons: props.reasons,
  });
});
const viewTitle = computed(() => {
  switch (view.value) {
    case 'won':
      return t('KANBAN.CARD.STATUS.MARK_AS_WON');
    case 'lost':
      return t('KANBAN.CARD.STATUS.MARK_AS_LOST');
    case 'reopen':
      return t('KANBAN.CARD.STATUS.REOPEN_OPPORTUNITY');
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

const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => props.slaHours)
  );
const dueAt = computed(() => props.card.due_at || props.card.dueAt);
const dueAtLabel = computed(() =>
  formatDateInput(dueAt.value).split('-').reverse().join('/')
);
const hasDueDate = computed(() => !!dueAtLabel.value);

const cardValue = computed(() => Number(props.card.value) || 0);
const formattedCardValue = computed(() =>
  formatCompactCurrency(cardValue.value)
);
const fullCardValue = computed(() => formatCurrency(cardValue.value));
const hasCardFacts = computed(
  () => cardValue.value > 0 || hasDueDate.value || !!stageTime.value
);

const openDetails = () => {
  emit('openDetails', props.card);
};

const resetView = () => {
  view.value = 'root';
  resetMoveTarget();
  moveTargetStage.value = null;
};

const closeMenu = hide => {
  resetView();
  hide?.();
};

const openView = nextView => {
  if (nextView === 'due') dueDateInput.value = formatDateInput(dueAt.value);
  if (nextView === 'move') {
    resetMoveTarget();
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

const onConfirmStatus = (type, reasonId, hide) => {
  onChangeStatus(statusPayloadFor(type, reasonId));
  closeMenu(hide);
};

const onSelectStatus = (type, hide) => {
  if (canSkipReason(type)) {
    onConfirmStatus(type, null, hide);
    return;
  }

  openView(type);
};

const openCard = event => {
  event.currentTarget?.focus?.();
  if (hasConversation.value) {
    emit('openConversation', props.card, event);
    return;
  }

  emit('openDetails', props.card);
};

const openActionsMenu = event => {
  if (props.variant !== 'list') return;

  event.preventDefault();
  event.stopPropagation();
  if (props.isBusy) return;

  event.currentTarget?.focus?.();
  actionsPopover.value?.showAt({ x: event.clientX, y: event.clientY });
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
    class="group relative cursor-pointer select-none rounded-lg transition-colors"
    :class="[
      variant === 'board'
        ? 'card-drag-handle border border-n-weak bg-n-surface-1 p-3 hover:border-n-brand'
        : 'flex w-full min-w-0 flex-wrap items-center gap-x-3 gap-y-1 px-2 py-2 text-left hover:bg-n-alpha-1',
      {
        'border-n-brand ring-1 ring-n-brand': variant === 'board' && isSelected,
        'border-l-2 border-n-ruby-9':
          variant === 'board' && stageSlaStatusValue === SLA_STALE,
        'no-drag': isBusy,
      },
    ]"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    @click="openCard"
    @contextmenu="openActionsMenu"
  >
    <label
      v-if="variant === 'board'"
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
      class="no-drag absolute top-1.5 z-10 inline-flex ltr:right-1.5 rtl:left-1.5"
      @click.stop
    >
      <Popover
        ref="actionsPopover"
        align="end"
        disable-mobile-view
        @hide="resetView"
      >
        <button
          v-if="variant === 'board'"
          type="button"
          data-testid="kanban-card-actions"
          class="no-drag flex size-8 items-center justify-center rounded-md border border-n-weak bg-n-surface-1 text-n-slate-11 shadow-sm hover:bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50"
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

            <div v-if="view === 'root'" class="p-2">
              <KanbanStatusMenuItems
                v-if="hasTerminals"
                testid-prefix="kanban-card"
                :is-open="isOpen"
                :disabled="isBusy"
                @select="type => onSelectStatus(type, hide)"
              />
              <button
                v-if="hasConversation"
                type="button"
                data-testid="kanban-card-open-conversation"
                :class="MENU_OPTION_CLASSES"
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
                :class="MENU_OPTION_CLASSES"
                :disabled="isBusy"
                @click="openConversationInNewTab(hide)"
              >
                <i class="i-lucide-external-link size-4" />
                {{ t('KANBAN.CARD.OPEN_IN_NEW_TAB') }}
              </button>
              <button
                type="button"
                data-testid="kanban-card-edit"
                :class="MENU_OPTION_CLASSES"
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
                class="justify-between"
                :class="[MENU_OPTION_CLASSES]"
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
                class="justify-between"
                :class="[MENU_OPTION_CLASSES]"
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
                class="justify-between"
                :class="[MENU_OPTION_CLASSES]"
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
                class="justify-between"
                :class="[MENU_OPTION_CLASSES]"
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
                class="justify-between"
                :class="[MENU_OPTION_CLASSES]"
                :disabled="isBusy"
                @click="openView('due')"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i class="i-lucide-calendar size-4" />
                  <span class="truncate">{{ t('KANBAN.CARD.DUE_DATE') }}</span>
                </span>
                <span class="flex flex-shrink-0 items-center gap-1">
                  <span v-if="hasDueDate" class="text-xs text-n-slate-11">
                    {{ dueAtLabel }}
                  </span>
                  <i class="i-lucide-chevron-right size-4" />
                </span>
              </button>
              <div :class="MENU_DIVIDER_CLASSES" />
              <button
                type="button"
                data-testid="kanban-card-remove"
                :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
                :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
                :class="[MENU_OPTION_CLASSES, MENU_OPTION_DESTRUCTIVE_CLASSES]"
                :disabled="isBusy"
                @click="removeCard(hide)"
              >
                <i class="i-lucide-trash size-4" />
                {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
              </button>
            </div>

            <div v-else-if="isStatusView" class="p-3">
              <KanbanStatusReasonForm
                :reason-type="view"
                :reasons="reasons"
                :required="view === 'lost' && lostReasonRequired"
                @back="goBack"
                @confirm="reasonId => onConfirmStatus(view, reasonId, hide)"
              />
            </div>

            <div v-else-if="view === 'move'" class="p-2">
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
                :class="MENU_DIVIDER_CLASSES"
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
                :class="MENU_OPTION_CLASSES"
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

            <div v-else-if="view === 'assign'" class="p-2">
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
                :class="MENU_OPTION_CLASSES"
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

            <div v-else-if="view === 'priority'" class="p-2">
              <button
                v-for="option in priorityOptions"
                :key="option.value"
                type="button"
                data-testid="kanban-card-priority-option"
                :data-selected="option.value === priority"
                :class="MENU_OPTION_CLASSES"
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

    <template v-if="variant === 'list'">
      <span class="flex flex-shrink-0 rounded-full" :title="contactName">
        <Avatar
          :name="contactName"
          :src="contactThumbnail"
          :size="28"
          rounded-full
        />
      </span>

      <span class="min-w-32 flex-1">
        <span
          class="block truncate text-sm font-medium leading-4 text-n-slate-12"
          :title="subject || contactName"
        >
          {{ subject || contactName }}
        </span>
        <span
          class="mt-1 flex min-w-0 items-center gap-1 text-xs leading-4 text-n-slate-11"
        >
          <span class="max-w-40 truncate" :title="contactName">
            {{ contactName }}
          </span>
          <ChannelIcon
            :inbox="namedInbox"
            class="size-3.5 flex-shrink-0 text-n-slate-11"
          />
          <InboxName :inbox="namedInbox" :show-icon="false" class="min-w-0" />
        </span>
      </span>

      <span class="flex flex-shrink-0 items-center gap-2 text-xs ms-auto">
        <CardPriorityIcon :priority="priority" show-empty class="!size-3.5" />
        <KanbanDueDateBadge v-if="hasDueDate" :due-at="dueAt" />

        <span
          v-if="visibleAssignees.length"
          class="-space-x-1 flex flex-shrink-0 items-center"
        >
          <span
            v-for="assignee in visibleAssignees"
            :key="assignee.id"
            data-testid="kanban-list-row-assignee"
            class="flex flex-shrink-0 rounded-full ring-2 ring-n-solid-2"
            :title="assignee.name"
          >
            <Avatar
              :name="assignee.name"
              :src="assignee.avatarUrl"
              :size="20"
              rounded-full
            />
          </span>
          <span
            v-if="extraAssigneeCount"
            data-testid="kanban-list-row-assignee-overflow"
            class="flex size-5 flex-shrink-0 items-center justify-center rounded-full bg-n-slate-3 text-[9px] font-medium leading-none text-n-slate-11 ring-2 ring-n-solid-2"
          >
            {{ extraAssigneeLabel }}
          </span>
        </span>

        <span
          v-if="cardValue > 0"
          data-testid="kanban-list-row-value"
          class="flex-shrink-0 font-medium text-n-slate-11"
          :title="fullCardValue"
        >
          {{ formattedCardValue }}
        </span>
      </span>
    </template>

    <div v-else class="min-w-0 text-left">
      <p
        v-if="subject"
        class="truncate text-sm font-semibold leading-4 text-n-slate-12 ltr:pr-8 rtl:pl-8"
        :title="subject"
      >
        {{ subject }}
      </p>

      <div
        v-if="labels.length"
        class="mt-1 flex flex-wrap gap-1 ltr:pr-8 rtl:pl-8"
      >
        <WootLabel
          v-for="label in labels"
          :key="label.title"
          :title="label.title"
          :bg-color="label.color"
          small
          class="!m-0 max-w-full"
        />
      </div>

      <div class="mt-3 flex min-w-0 items-center gap-2">
        <span
          data-testid="kanban-card-contact-avatar"
          class="flex flex-shrink-0 rounded-full"
          :title="contactName"
        >
          <Avatar
            :name="contactName"
            :src="contactThumbnail"
            :size="28"
            rounded-full
          />
        </span>

        <div class="min-w-0 flex-1">
          <h4
            class="truncate text-xs font-medium leading-4 text-n-slate-12"
            :title="contactName"
          >
            {{ contactName }}
          </h4>

          <div class="mt-1 flex min-w-0 items-center gap-1 text-xs leading-4">
            <ChannelIcon
              :inbox="namedInbox"
              class="size-3.5 flex-shrink-0 text-n-slate-11"
            />
            <InboxName :inbox="namedInbox" :show-icon="false" class="min-w-0" />
          </div>
        </div>

        <div
          v-if="visibleAssignees.length"
          class="-space-x-1 flex flex-shrink-0 items-center"
        >
          <span
            v-for="assignee in visibleAssignees"
            :key="assignee.id"
            data-testid="kanban-card-assignee"
            class="flex flex-shrink-0 rounded-full ring-2 ring-n-surface-1"
            :title="assignee.name"
          >
            <Avatar
              :name="assignee.name"
              :src="assignee.avatarUrl"
              :size="20"
              rounded-full
            />
          </span>
          <span
            v-if="extraAssigneeCount"
            data-testid="kanban-card-assignee-overflow"
            class="flex size-5 flex-shrink-0 items-center justify-center rounded-full bg-n-slate-3 text-[9px] font-medium leading-none text-n-slate-11 ring-2 ring-n-surface-1"
          >
            {{ extraAssigneeLabel }}
          </span>
        </div>
      </div>

      <div
        data-testid="kanban-card-meta"
        class="mt-3 text-xs leading-4 text-n-slate-10"
      >
        <div class="flex min-w-0 items-center justify-between gap-2">
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

          <span class="ms-auto inline-flex flex-shrink-0">
            <CardPriorityIcon
              :priority="priority"
              show-empty
              class="!size-3.5"
            />
          </span>
        </div>

        <div
          v-if="hasCardFacts"
          class="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1"
        >
          <span
            v-if="cardValue > 0"
            data-testid="kanban-card-value"
            class="inline-flex flex-shrink-0 items-center font-medium text-n-slate-11"
            :title="fullCardValue"
          >
            {{ formattedCardValue }}
          </span>
          <KanbanDueDateBadge v-if="hasDueDate" :due-at="dueAt" />
          <span
            v-if="stageTime"
            class="inline-flex flex-shrink-0 items-center gap-1"
            :class="stageSlaClasses"
            :title="stageTimeTitle"
            :aria-label="
              stageSlaStatusValue === SLA_STALE
                ? t('KANBAN.CARD.SLA_STALE')
                : undefined
            "
          >
            <i class="i-lucide-clock size-3 flex-shrink-0" />
            <span>{{ stageTime }}</span>
          </span>
        </div>
      </div>
    </div>
  </article>
</template>
