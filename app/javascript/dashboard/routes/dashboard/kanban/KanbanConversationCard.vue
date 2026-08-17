<script setup>
import { computed, ref, toRef } from 'vue';
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
import Popover from 'dashboard/components-next/popover/Popover.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
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
  'assignAgent',
  'updateDueDate',
]);

const { t } = useI18n();
const store = useStore();
const view = ref('root');
const dueDateInput = ref('');
const { isTerminalStage } = useKanbanStageOrder({
  stages: toRef(props, 'stages'),
  wonStageId: toRef(props, 'wonStageId'),
  lostStageId: toRef(props, 'lostStageId'),
});
const viewTitle = computed(() => {
  switch (view.value) {
    case 'move':
      return t('KANBAN.CARD.MOVE_TO');
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
const moveTargets = computed(() =>
  props.stages.filter(
    stage =>
      Number(stage.id) !== Number(props.card.kanbanStageId) &&
      !isTerminalStage(stage)
  )
);
const subject = computed(() => props.card.subject || '');
const labels = computed(() => props.card.labels || props.card.label_list || []);

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
};

const closeMenu = hide => {
  resetView();
  hide?.();
};

const openView = nextView => {
  if (nextView === 'due') dueDateInput.value = formatDateInput(dueAt.value);
  view.value = nextView;
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
  emit('moveToStage', props.card, stage.id);
  closeMenu(hide);
};

const onAssignAgent = (user, hide) => {
  emit('assignAgent', props.card, user.id);
  closeMenu(hide);
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
</script>

<template>
  <article
    tabindex="0"
    class="card-drag-handle group relative cursor-pointer rounded-lg border border-n-weak bg-n-surface-1 p-3 transition-colors hover:border-n-brand"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    @click="openCard"
  >
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
              @back="view = 'root'"
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
              <p
                v-if="!moveTargets.length"
                class="px-3 py-2 text-sm text-n-slate-10"
              >
                {{
                  isTerminalStage({ id: card.kanbanStageId })
                    ? t('KANBAN.CARD.TERMINAL_STAGE_HINT')
                    : t('KANBAN.CARD.NO_REGULAR_STAGES')
                }}
              </p>
              <button
                v-for="stage in moveTargets"
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
            +{{ extraAssigneeCount }}
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

      <div v-if="labels.length" class="mt-1 flex flex-wrap gap-1">
        <span
          v-for="label in labels"
          :key="label"
          class="max-w-full truncate rounded-full bg-n-slate-3 px-1.5 py-0.5 text-[11px] font-medium leading-4 text-n-slate-11"
        >
          {{ label }}
        </span>
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
