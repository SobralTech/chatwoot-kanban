<script setup>
import { computed, ref, watch } from 'vue';
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
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import KanbanCardStatusBadge from '../../kanban/KanbanCardStatusBadge.vue';
import KanbanStageSelect from '../../kanban/KanbanStageSelect.vue';
import KanbanConversationCardMenu from './KanbanConversationCardMenu.vue';
import {
  MENU_OPTION_CLASSES,
  MENU_SURFACE_CLASSES,
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

// The container camelizes every payload before it gets here, so the wire's
// snake_case never reaches this component.
const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');
const dueDateInput = ref('');

const accountLabelList = computed(() => accountLabels?.value || []);
const cardBoard = computed(() => props.card.kanbanBoard || props.board);
const wonStageId = computed(() => cardBoard.value.wonStageId);
const lostStageId = computed(() => cardBoard.value.lostStageId);
const lostReasonRequired = computed(() => cardBoard.value.lostReasonRequired);
const cardStage = computed(() => props.card.kanbanStage || {});
const cardId = computed(() => props.card.id);
// The sidebar payload nests the stage instead of sending its id on the card.
const stageId = computed(() =>
  Number(props.card.kanbanStageId ?? cardStage.value.id)
);
const subject = computed(() => props.card.subject || '');
const priority = computed(() => props.card.priority ?? '');
const dueAt = computed(() => props.card.dueAt ?? null);
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
  const cardLabels = props.card.labels || [];

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
// Chips read at a glance; the rest stay behind the counter next to them.
const visibleLabels = computed(() => labels.value.slice(0, 3));
const extraLabelCount = computed(() =>
  Math.max(labels.value.length - visibleLabels.value.length, 0)
);
const assignees = computed(() => props.card.assignees || []);
const cardValue = computed(() => Number(props.card.value) || 0);
const formattedValue = computed(() => formatCurrency(cardValue.value));
const boardName = computed(
  () => cardBoard.value?.name || t('KANBAN.CARD.UNKNOWN_BOARD')
);
const stageOptions = computed(() => props.regularStages || []);
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
    computed(() => cardStage.value.slaHours)
  );

watch(
  dueAt,
  value => {
    dueDateInput.value = formatDateInput(value);
  },
  { immediate: true }
);

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
        class="flex min-w-0 flex-1 items-center gap-1 p-0 text-left font-medium text-n-slate-12 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
        :title="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD')"
        :disabled="isBusy"
        @click.stop="openMove"
      >
        <span class="min-w-0 truncate">{{ boardName }}</span>
        <!-- Without the chevron nothing tells the user the funnel can change. -->
        <i class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-10" />
      </button>
      <KanbanConversationCardMenu
        :card="card"
        :board="cardBoard"
        :account-labels="accountLabelList"
        :assignable-users="assignableUsers"
        :is-assignees-loading="isAssigneesLoading"
        :is-busy="isBusy"
        @change-status="emit('changeStatus', card, $event)"
        @copy-id="copyCardId"
        @delete="emit('delete', card)"
        @load-assignees="showAssignees"
        @open-details="openDetails"
        @open-move="openMove"
        @update-priority="value => emit('updatePriority', card, value)"
        @update-due-date="value => emit('updateDueDate', card, value)"
        @update-labels="titles => emit('updateLabels', card, titles)"
        @update-assignees="ids => emit('updateAssignees', card, ids)"
      />
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

    <div
      v-if="visibleLabels.length"
      data-testid="kanban-conversation-card-labels"
      class="-mb-1 mt-1.5 flex min-w-0 flex-wrap items-center"
    >
      <WootLabel
        v-for="label in visibleLabels"
        :key="label.id || label.title"
        data-testid="kanban-conversation-card-label"
        :title="label.title"
        :color="label.color"
        variant="smooth"
        small
        class="max-w-[8rem]"
      />
      <span
        v-if="extraLabelCount"
        class="mb-1 text-xs text-n-slate-10"
        :title="labelTitles.join(', ')"
      >
        {{ t('KANBAN.OVERVIEW.EXTRA_COUNT', { count: extraLabelCount }) }}
      </span>
    </div>

    <div class="mt-2 flex min-w-0 items-center gap-2">
      <KanbanStageSelect
        :model-value="stageId"
        :stages="stageOptions"
        :current-stage="cardStage"
        :disabled="isBusy"
        class="min-w-0 flex-1"
        data-testid="kanban-conversation-card-stage"
        @update:model-value="emit('updateStage', card, $event)"
      />

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
          <div class="grid w-52 gap-1" :class="[MENU_SURFACE_CLASSES]">
            <button
              v-for="option in priorityOptions"
              :key="option.value"
              type="button"
              data-testid="kanban-conversation-card-priority-option"
              :class="MENU_OPTION_CLASSES"
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
          <div class="grid w-56 gap-2" :class="[MENU_SURFACE_CLASSES]">
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
        </button>
        <template #content>
          <div class="w-80" :class="[MENU_SURFACE_CLASSES]">
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
              :src="assignee.avatarUrl"
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
          <div class="w-72" :class="[MENU_SURFACE_CLASSES]">
            <ul class="grid gap-1">
              <li v-for="user in assignableUsers" :key="user.id">
                <button
                  type="button"
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
