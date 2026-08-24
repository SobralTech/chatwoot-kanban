<script setup>
import { computed, ref, watch } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import KanbanCardStatusBadge from '../../kanban/KanbanCardStatusBadge.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  regularStages: {
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
  isHighlighted: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'changeStatus',
  'delete',
  'loadAssignees',
  'openDetails',
  'openMove',
  'updateAssignees',
  'updateDueDate',
  'updateLabels',
  'updatePriority',
  'updateStage',
]);

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');
const dueDateInput = ref('');
const isActionsMenuOpen = ref(false);

const accountLabelList = computed(() => accountLabels?.value || []);
const cardBoard = computed(
  () => props.card.kanbanBoard || props.card.kanban_board || props.board
);
const wonStageId = computed(
  () => cardBoard.value.wonStageId ?? cardBoard.value.won_stage_id
);
const lostStageId = computed(
  () => cardBoard.value.lostStageId ?? cardBoard.value.lost_stage_id
);
const lostReasonRequired = computed(
  () =>
    cardBoard.value.lostReasonRequired ?? cardBoard.value.lost_reason_required
);
const cardStage = computed(
  () => props.card.kanbanStage || props.card.kanban_stage || {}
);
const cardId = computed(() => props.card.id);
const stageId = computed(() =>
  Number(
    props.card.kanbanStageId ?? props.card.kanban_stage_id ?? cardStage.value.id
  )
);
const subject = computed(() => props.card.subject || '');
const priority = computed(
  () =>
    props.card.priority ??
    props.card.cardPriority ??
    props.card.card_priority ??
    ''
);
const dueAt = computed(() => props.card.dueAt ?? props.card.due_at ?? null);
const priorityOptions = computed(() => [
  {
    value: '',
    label: t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
  },
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
const labels = computed(() => {
  const cardLabels = props.card.labels || props.card.label_list || [];

  return cardLabels.map(label => {
    if (typeof label !== 'string') return label;

    return (
      accountLabelList.value.find(
        accountLabel => accountLabel.title === label
      ) || {
        title: label,
      }
    );
  });
});
const labelTitles = computed(() =>
  labels.value.map(label => label.title).filter(Boolean)
);
const assignees = computed(() => props.card.assignees || []);
const cardValue = computed(() => Number(props.card.value) || 0);
const formattedValue = computed(() => formatCurrency(cardValue.value));
const boardName = computed(
  () => cardBoard.value?.name || t('KANBAN.CARD.UNKNOWN_BOARD')
);
const stageName = computed(
  () => cardStage.value?.name || t('KANBAN.CARD.UNKNOWN_STAGE')
);
const stageOptions = computed(() => props.regularStages || []);
const canChangeStage = computed(() =>
  stageOptions.value.some(stage => Number(stage.id) === stageId.value)
);
const stageSelectValue = computed(() => String(stageId.value || ''));
const dueDateLabel = computed(() => {
  if (!dueAt.value) return '';

  const date = new Date(dueAt.value);
  return Number.isNaN(date.getTime()) ? '' : format(date, 'dd/MM');
});
const dueDateTitle = computed(() =>
  dueDateLabel.value
    ? t('KANBAN.CARD.DUE_DATE')
    : t('CONVERSATION_SIDEBAR.KANBAN.SET_DUE_DATE')
);
const priorityLabel = computed(() => {
  const option = priorityOptions.value.find(
    item => item.value === priority.value
  );
  return option?.label || t('CONVERSATION.PRIORITY.OPTIONS.NONE');
});
const selectedAssigneeIds = computed(() =>
  assignees.value.map(assignee => assignee.id)
);
const primaryAssignees = computed(() => assignees.value.slice(0, 2));
const extraAssigneeCount = computed(() =>
  Math.max(assignees.value.length - 2, 0)
);
const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => cardStage.value.slaHours ?? cardStage.value.sla_hours)
  );

watch(
  dueAt,
  value => {
    dueDateInput.value = formatDateInput(value);
  },
  { immediate: true }
);

const onStageChange = event => {
  emit('updateStage', props.card, Number(event.target.value));
};

const onPriorityChange = (value, hide) => {
  emit('updatePriority', props.card, value);
  hide?.();
};

const onDueDateChange = (value, hide) => {
  emit('updateDueDate', props.card, value);
  hide?.();
};

const onLabelAdd = label => {
  const title = label?.title || label;
  if (!title || labelTitles.value.includes(title)) return;

  emit('updateLabels', props.card, [...labelTitles.value, title]);
};

const onLabelRemove = title => {
  emit(
    'updateLabels',
    props.card,
    labelTitles.value.filter(labelTitle => labelTitle !== title)
  );
};

const onAssigneeToggle = user => {
  const nextIds = selectedAssigneeIds.value.includes(user.id)
    ? selectedAssigneeIds.value.filter(id => id !== user.id)
    : [...selectedAssigneeIds.value, user.id];

  emit('updateAssignees', props.card, nextIds);
};

const copyCardId = async () => {
  await copyTextToClipboard(cardId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const showAssignees = () => emit('loadAssignees', props.card);
const openDetails = () => emit('openDetails', props.card);
const openMove = () => emit('openMove', props.card);

const closeActionsMenu = () => {
  isActionsMenuOpen.value = false;
};

const actionMenuSections = computed(() => [
  {
    items: [
      {
        action: 'openDetails',
        value: 'openDetails',
        icon: 'i-lucide-pencil',
        label: t('CONVERSATION_SIDEBAR.KANBAN.EDIT_DETAILS'),
        disabled: props.isBusy,
      },
      {
        action: 'openMove',
        value: 'openMove',
        icon: 'i-lucide-corner-up-right',
        label: t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD'),
        disabled: props.isBusy,
      },
      {
        action: 'copyCardId',
        value: 'copyCardId',
        icon: 'i-lucide-copy',
        label: t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID_WITH_ID', {
          id: cardId.value,
        }),
        disabled: props.isBusy,
      },
    ],
  },
  {
    items: [
      {
        action: 'delete',
        value: 'delete',
        icon: 'i-lucide-trash-2',
        label: t('KANBAN.ACTIONS.REMOVE_CARD'),
        disabled: props.isBusy,
      },
    ],
  },
]);

const menuActions = {
  openDetails,
  openMove,
  copyCardId,
  delete: () => emit('delete', props.card),
};

const onMenuAction = ({ value }) => {
  closeActionsMenu();
  menuActions[value]();
};
const onCardKeydown = event => {
  if (event.target !== event.currentTarget) return;

  event.preventDefault();
  openDetails();
};
const onSubjectKeydown = event => {
  if (event.key !== 'Enter' && event.key !== ' ') return;

  event.preventDefault();
  event.stopPropagation();
  openDetails();
};
</script>

<template>
  <article
    tabindex="0"
    data-testid="kanban-conversation-card"
    class="min-w-0 rounded-lg border border-n-weak bg-n-surface-1 p-3 text-sm transition-colors focus:outline-none focus:ring-1 focus:ring-n-brand"
    :class="{
      'border-n-brand ring-1 ring-n-brand': isHighlighted,
      'border-l-2 border-n-ruby-9': stageSlaStatusValue === 'stale',
    }"
    :data-card-id="cardId"
    @keydown.enter="onCardKeydown"
    @keydown.space="onCardKeydown"
  >
    <div class="flex min-w-0 items-center gap-2">
      <button
        type="button"
        data-testid="kanban-conversation-card-board"
        class="min-w-0 flex-1 truncate text-left font-medium text-n-slate-12 hover:text-n-brand"
        :title="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD')"
        :disabled="isBusy"
        @click.stop="openMove"
      >
        {{ boardName }}
      </button>
      <div
        v-on-click-outside="closeActionsMenu"
        class="relative flex flex-shrink-0 items-center"
      >
        <button
          type="button"
          data-testid="kanban-conversation-card-actions"
          class="flex size-7 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :aria-label="t('KANBAN.CARD.ACTIONS_MENU')"
          :disabled="isBusy"
          @click.stop="isActionsMenuOpen = !isActionsMenuOpen"
        >
          <i v-if="isBusy" class="i-lucide-loader-circle size-4 animate-spin" />
          <i v-else class="i-lucide-more-vertical size-4" />
        </button>

        <DropdownMenu
          v-if="isActionsMenuOpen"
          data-testid="kanban-conversation-card-actions-menu"
          :menu-sections="actionMenuSections"
          class="top-full mt-1 ltr:right-0 rtl:left-0"
          @action="onMenuAction"
        />
      </div>
    </div>

    <p
      data-testid="kanban-conversation-card-subject"
      class="mt-1 cursor-pointer truncate text-sm text-n-slate-11 hover:text-n-brand"
      :title="subject"
      role="button"
      tabindex="0"
      :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.EDIT_DETAILS')"
      @click.stop="openDetails"
      @keydown="onSubjectKeydown"
    >
      {{ subject }}
    </p>

    <div class="mt-2 flex min-w-0 items-center gap-2">
      <div
        v-if="canChangeStage"
        class="relative flex min-w-0 flex-1 items-center gap-1.5 rounded-md bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
      >
        <span
          class="size-2 flex-shrink-0 rounded-full bg-n-brand"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1 truncate">{{ stageName }}</span>
        <i class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-10" />
        <select
          :value="stageSelectValue"
          data-testid="kanban-conversation-card-stage"
          class="absolute inset-0 cursor-pointer opacity-0"
          :aria-label="t('KANBAN.CARD.MOVE_TO_STAGE')"
          :disabled="isBusy"
          @change="onStageChange"
        >
          <option
            v-for="stage in stageOptions"
            :key="stage.id"
            :value="stage.id"
          >
            {{ stage.name }}
          </option>
        </select>
      </div>
      <span
        v-else
        class="min-w-0 flex-1 truncate rounded-md bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
      >
        {{ stageName }}
      </span>

      <span class="no-drag flex-shrink-0" @click.stop>
        <KanbanCardStatusBadge
          :kanban-stage-id="stageId"
          :won-stage-id="Number(wonStageId) || null"
          :lost-stage-id="Number(lostStageId) || null"
          :reasons="cardBoard.reasons || []"
          :lost-reason-required="Boolean(lostReasonRequired)"
          :disabled="isBusy"
          @change="emit('changeStatus', card, $event)"
        />
      </span>
    </div>

    <div
      class="mt-2 flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 text-xs text-n-slate-10"
    >
      <span
        v-if="cardValue > 0"
        data-testid="kanban-conversation-card-value"
        class="inline-flex items-center font-medium text-n-slate-11"
      >
        {{ formattedValue }}
      </span>
      <Popover align="start" disable-mobile-view>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md px-1 py-0.5 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :title="priorityLabel"
          :aria-label="priorityLabel"
          :disabled="isBusy"
        >
          <CardPriorityIcon :priority="priority" show-empty class="!size-3.5" />
        </button>
        <template #content="{ hide }">
          <div class="grid w-52 gap-0.5 rounded-xl p-1">
            <button
              v-for="option in priorityOptions"
              :key="option.value"
              type="button"
              data-testid="kanban-conversation-card-priority-option"
              class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-xs hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="isBusy"
              @click="onPriorityChange(option.value, hide)"
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
        </template>
      </Popover>
      <Popover align="start" disable-mobile-view>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md px-1 py-0.5 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :title="dueDateTitle"
          :aria-label="dueDateTitle"
          :disabled="isBusy"
        >
          <i class="i-lucide-calendar size-3" />
          <span v-if="dueDateLabel">{{ dueDateLabel }}</span>
        </button>
        <template #content="{ hide }">
          <div class="grid w-56 gap-2 rounded-xl p-3">
            <label class="grid gap-1 text-xs font-medium text-n-slate-12">
              {{ t('KANBAN.CARD.DUE_DATE') }}
              <input
                v-model="dueDateInput"
                type="date"
                class="h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12"
                :disabled="isBusy"
                @change="onDueDateChange(dueDateInput, hide)"
              />
            </label>
            <button
              type="button"
              class="justify-self-end text-xs text-n-slate-11 hover:text-n-slate-12"
              :disabled="isBusy"
              @click="onDueDateChange('', hide)"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE') }}
            </button>
          </div>
        </template>
      </Popover>
      <Popover align="start" disable-mobile-view>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-md px-1 py-0.5 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :title="t('CONVERSATION_SIDEBAR.KANBAN.LABELS')"
          :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.LABELS')"
          :disabled="isBusy"
        >
          <i class="i-lucide-tags size-3" />
          <span>{{ labelTitles.length }}</span>
        </button>
        <template #content>
          <div class="w-80 rounded-xl p-2">
            <LabelDropdown
              :account-labels="accountLabelList"
              :selected-labels="labelTitles"
              :allow-creation="false"
              @add="onLabelAdd"
              @remove="onLabelRemove"
            />
          </div>
        </template>
      </Popover>
      <Popover align="start" disable-mobile-view @show="showAssignees">
        <button
          type="button"
          class="inline-flex min-w-0 items-center gap-1 rounded-md px-1 py-0.5 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
          :title="t('KANBAN.CARD.ASSIGN_TO')"
          :aria-label="t('KANBAN.CARD.ASSIGN_TO')"
          :disabled="isBusy"
        >
          <i
            v-if="isAssigneesLoading"
            class="i-lucide-loader-circle size-3 animate-spin"
          />
          <template v-else>
            <Avatar
              v-for="assignee in primaryAssignees"
              :key="assignee.id"
              :name="assignee.name"
              :src="assignee.avatarUrl || assignee.avatar_url"
              :size="18"
              rounded-full
            />
            <i v-if="!assignees.length" class="i-lucide-user-round size-3" />
            <span v-if="extraAssigneeCount">
              {{
                t('KANBAN.OVERVIEW.EXTRA_COUNT', { count: extraAssigneeCount })
              }}
            </span>
          </template>
        </button>
        <template #content>
          <div class="w-72 rounded-xl p-2">
            <ul class="grid gap-1">
              <li v-for="user in assignableUsers" :key="user.id">
                <button
                  type="button"
                  class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
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
                    :src="user.avatarUrl || user.avatar_url"
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
        </template>
      </Popover>
      <span
        v-if="stageTime"
        class="inline-flex items-center gap-1"
        :class="stageSlaClasses || 'text-n-slate-10'"
        :title="stageTimeTitle"
        :aria-label="
          stageSlaStatusValue === 'stale'
            ? t('KANBAN.CARD.SLA_STALE')
            : t('CONVERSATION_SIDEBAR.KANBAN.IN_STAGE_FOR', { age: stageTime })
        "
      >
        <i class="i-lucide-clock size-3" />
        {{ stageTime }}
      </span>
    </div>
  </article>
</template>
