<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import { CARD_STATUS_TYPES } from 'dashboard/helper/kanbanCardStatus';
import { useKanbanCardStatusActions } from 'dashboard/composables/useKanbanCardStatusActions';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';
import KanbanDueDatePicker from '../../kanban/KanbanDueDatePicker.vue';
import KanbanMenuHeader from '../../kanban/KanbanMenuHeader.vue';
import KanbanStatusMenuItems from '../../kanban/KanbanStatusMenuItems.vue';
import KanbanStatusReasonForm from '../../kanban/KanbanStatusReasonForm.vue';
import {
  MENU_DIVIDER_CLASSES,
  MENU_OPTION_CLASSES,
  MENU_OPTION_DESTRUCTIVE_CLASSES,
} from '../../kanban/menuClasses';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  accountLabels: {
    type: Array,
    default: () => [],
  },
  // Resolved by the card, which already needs the full label objects for its
  // chips; the menu only ever reads the titles.
  labelTitles: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
  isAssigneesLoading: {
    type: Boolean,
    default: false,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'changeStatus',
  'copyId',
  'delete',
  'loadAssignees',
  'openDetails',
  'openFunnel',
  'openMove',
  'updateAssignees',
  'updateDueDate',
  'updateLabels',
  'updatePriority',
]);

const { t } = useI18n();

const popoverRef = ref(null);
const view = ref('root');
const dueDateInput = ref('');

// The sidebar payload nests the stage instead of sending its id on the card.
const cardStage = computed(() => props.card.kanbanStage || {});
const { hasTerminals, isOpen, canSkipReason, statusPayloadFor } =
  useKanbanCardStatusActions({
    stageId: computed(() => props.card.kanbanStageId ?? cardStage.value.id),
    wonStageId: computed(() => props.board.wonStageId),
    lostStageId: computed(() => props.board.lostStageId),
    reasons: computed(() => props.board.reasons),
    lostReasonRequired: computed(() => props.board.lostReasonRequired),
  });
const isStatusView = computed(() => CARD_STATUS_TYPES.includes(view.value));

const priority = computed(() => props.card.priority ?? '');
const dueAt = computed(() => props.card.dueAt ?? null);
const dueDateLabel = computed(() => {
  const dateValue = formatDateInput(dueAt.value);

  return dateValue ? dateValue.split('-').reverse().join('/') : '';
});
const assignees = computed(() => props.card.assignees || []);
const selectedAssigneeIds = computed(() =>
  assignees.value.map(assignee => assignee.id)
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

const viewTitle = computed(() => {
  switch (view.value) {
    case 'won':
      return t('KANBAN.CARD.STATUS.MARK_AS_WON');
    case 'lost':
      return t('KANBAN.CARD.STATUS.MARK_AS_LOST');
    case 'reopen':
      return t('KANBAN.CARD.STATUS.REOPEN_OPPORTUNITY');
    case 'labels':
      return t('CONTACT_PANEL.LABELS.LABEL_SELECT.TITLE');
    case 'assign':
      return t('KANBAN.CARD.ASSIGN_TO');
    case 'priority':
      return t('KANBAN.CARD.CHANGE_PRIORITY');
    case 'due':
      return t('KANBAN.CARD.DUE_DATE');
    default:
      return t('KANBAN.CARD.ACTIONS_MENU');
  }
});

const resetView = () => {
  view.value = 'root';
};

const closeMenu = hide => {
  resetView();
  dueDateInput.value = '';
  hide?.();
};

const openView = nextView => {
  if (nextView === 'due') dueDateInput.value = formatDateInput(dueAt.value);
  view.value = nextView;
};

// Entry point for the card's read-only rows: a chip or avatar click lands
// straight on the matching sub-view, with the popover already open.
const openAtView = nextView => {
  if (nextView === 'assign') emit('loadAssignees');
  openView(nextView);
  popoverRef.value?.show();
};

defineExpose({ openAtView });

const changeStatusTo = (type, reasonId, hide) => {
  emit('changeStatus', statusPayloadFor(type, reasonId));
  closeMenu(hide);
};

const onSelectStatus = (type, hide) => {
  if (canSkipReason(type)) {
    changeStatusTo(type, null, hide);
    return;
  }

  openView(type);
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || props.labelTitles.includes(title)) return;

  emit('updateLabels', [...props.labelTitles, title]);
};

const onRemoveLabel = title => {
  emit(
    'updateLabels',
    props.labelTitles.filter(labelTitle => labelTitle !== title)
  );
};

const onAssigneeToggle = user => {
  const nextIds = selectedAssigneeIds.value.includes(user.id)
    ? selectedAssigneeIds.value.filter(id => id !== user.id)
    : [...selectedAssigneeIds.value, user.id];

  emit('updateAssignees', nextIds);
};

const onSelectDueDate = (value, hide) => {
  emit('updateDueDate', value);
  closeMenu(hide);
};
</script>

<template>
  <Popover ref="popoverRef" align="end" disable-mobile-view @hide="resetView">
    <button
      type="button"
      data-testid="kanban-conversation-card-actions"
      class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50"
      :aria-label="t('KANBAN.CARD.ACTIONS_MENU')"
      :title="t('KANBAN.CARD.ACTIONS_MENU')"
      :disabled="isBusy"
    >
      <i v-if="isBusy" class="i-lucide-loader-circle size-5 animate-spin" />
      <i v-else class="i-lucide-more-vertical size-5" />
    </button>

    <template #content="{ hide }">
      <div
        data-testid="kanban-conversation-card-actions-menu"
        class="w-72 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl text-sm text-n-slate-12"
      >
        <KanbanMenuHeader
          :title="viewTitle"
          :show-back="view !== 'root'"
          @back="resetView"
          @close="closeMenu(hide)"
        />

        <div v-if="view === 'root'" class="p-2">
          <KanbanStatusMenuItems
            v-if="hasTerminals"
            testid-prefix="kanban-conversation-card-menu"
            :is-open="isOpen"
            :disabled="isBusy"
            @select="type => onSelectStatus(type, hide)"
          />

          <button
            type="button"
            data-testid="kanban-conversation-card-menu-open-funnel"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="
              closeMenu(hide);
              emit('openFunnel');
            "
          >
            <i class="i-lucide-panels-top-left size-4" />
            {{ t('KANBAN.OPPORTUNITY_DETAILS.OPEN_IN_BOARD') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-edit"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="
              closeMenu(hide);
              emit('openDetails');
            "
          >
            <i class="i-lucide-pencil size-4" />
            {{ t('CONVERSATION_SIDEBAR.KANBAN.EDIT_DETAILS') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-labels"
            class="justify-between"
            :class="[MENU_OPTION_CLASSES]"
            :disabled="isBusy"
            @click="openView('labels')"
          >
            <span class="flex min-w-0 items-center gap-2">
              <i class="i-lucide-tags size-4" />
              <span class="truncate">
                {{ t('CONVERSATION_SIDEBAR.KANBAN.LABELS') }}
              </span>
            </span>
            <span class="flex flex-shrink-0 items-center gap-1">
              <span v-if="labelTitles.length" class="text-xs text-n-slate-11">
                {{ labelTitles.length }}
              </span>
              <i class="i-lucide-chevron-right size-4" />
            </span>
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-assign"
            class="justify-between"
            :class="[MENU_OPTION_CLASSES]"
            :disabled="isBusy"
            @click="
              emit('loadAssignees');
              openView('assign');
            "
          >
            <span class="flex min-w-0 items-center gap-2">
              <i class="i-lucide-user-round size-4" />
              <span class="truncate">{{ t('KANBAN.CARD.ASSIGN_TO') }}</span>
            </span>
            <i class="i-lucide-chevron-right size-4 flex-shrink-0" />
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-priority"
            class="justify-between"
            :class="[MENU_OPTION_CLASSES]"
            :disabled="isBusy"
            @click="openView('priority')"
          >
            <span class="flex min-w-0 items-center gap-2">
              <i class="i-lucide-signal size-4" />
              <span class="truncate">
                {{ t('KANBAN.CARD.CHANGE_PRIORITY') }}
              </span>
            </span>
            <i class="i-lucide-chevron-right size-4 flex-shrink-0" />
          </button>
          <button
            v-if="isOpen"
            type="button"
            data-testid="kanban-conversation-card-menu-due-date"
            class="justify-between"
            :class="[MENU_OPTION_CLASSES]"
            :disabled="isBusy"
            @click="openView('due')"
          >
            <span class="flex min-w-0 items-center gap-2">
              <i class="i-lucide-calendar size-4" />
              <span class="truncate">
                {{ t('CONVERSATION_SIDEBAR.KANBAN.SET_DUE_DATE') }}
              </span>
            </span>
            <span class="flex flex-shrink-0 items-center gap-1">
              <span v-if="dueDateLabel" class="text-xs text-n-slate-11">
                {{ dueDateLabel }}
              </span>
              <i class="i-lucide-chevron-right size-4" />
            </span>
          </button>

          <div :class="MENU_DIVIDER_CLASSES" />
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-move"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="
              closeMenu(hide);
              emit('openMove');
            "
          >
            <i class="i-lucide-corner-up-right size-4" />
            {{ t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD') }}
          </button>
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-copy-id"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="
              closeMenu(hide);
              emit('copyId');
            "
          >
            <i class="i-lucide-copy size-4" />
            {{
              t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID_WITH_ID', {
                id: card.id,
              })
            }}
          </button>

          <div :class="MENU_DIVIDER_CLASSES" />
          <button
            type="button"
            data-testid="kanban-conversation-card-menu-delete"
            :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
            :class="[MENU_OPTION_CLASSES, MENU_OPTION_DESTRUCTIVE_CLASSES]"
            :disabled="isBusy"
            @click="
              closeMenu(hide);
              emit('delete');
            "
          >
            <i class="i-lucide-trash-2 size-4" />
            {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
          </button>
        </div>

        <div v-else-if="isStatusView" class="p-3">
          <KanbanStatusReasonForm
            :reason-type="view"
            :reasons="board.reasons || []"
            :required="view === 'lost' && Boolean(board.lostReasonRequired)"
            @back="resetView"
            @confirm="reasonId => changeStatusTo(view, reasonId, hide)"
          />
        </div>

        <div v-else-if="view === 'labels'" class="p-2">
          <LabelDropdown
            :account-labels="accountLabels"
            :selected-labels="labelTitles"
            :allow-creation="false"
            @add="onAddLabel"
            @remove="onRemoveLabel"
          />
        </div>

        <div v-else-if="view === 'assign'" class="p-2">
          <p
            v-if="isAssigneesLoading"
            class="px-2 py-1.5 text-sm text-n-slate-10"
          >
            <i
              class="i-lucide-loader-circle mr-1 inline-block size-3 animate-spin"
            />
          </p>
          <ul class="grid gap-1">
            <li v-for="user in assignableUsers" :key="user.id">
              <button
                type="button"
                data-testid="kanban-conversation-card-menu-assignee"
                :class="MENU_OPTION_CLASSES"
                :disabled="isBusy"
                @click="onAssigneeToggle(user)"
              >
                <input
                  type="checkbox"
                  class="pointer-events-none"
                  :checked="selectedAssigneeIds.includes(user.id)"
                  tabindex="-1"
                />
                <Avatar
                  :name="user.name"
                  :src="user.avatarUrl"
                  :size="20"
                  rounded-full
                />
                <span class="min-w-0 flex-1 truncate">{{ user.name }}</span>
              </button>
            </li>
          </ul>
          <p
            v-if="!isAssigneesLoading && !assignableUsers.length"
            class="mb-0 px-2 py-1.5 text-sm text-n-slate-11"
          >
            {{ t('KANBAN.CARD.NO_ASSIGNABLE_USERS') }}
          </p>
        </div>

        <div v-else-if="view === 'priority'" class="p-2">
          <button
            v-for="option in priorityOptions"
            :key="option.value"
            type="button"
            data-testid="kanban-conversation-card-priority-option"
            :data-selected="option.value === priority"
            :class="MENU_OPTION_CLASSES"
            :disabled="isBusy"
            @click="
              emit('updatePriority', option.value);
              closeMenu(hide);
            "
          >
            <CardPriorityIcon
              :priority="option.value"
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
            data-testid="kanban-conversation-card-due-date-picker"
            :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
            :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
            :disabled="isBusy"
            @change="onSelectDueDate($event, hide)"
          />
        </div>
      </div>
    </template>
  </Popover>
</template>
