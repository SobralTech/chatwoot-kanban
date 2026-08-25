<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { differenceInCalendarDays, format } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';
import { SLA_STALE, SLA_WARNING } from 'dashboard/helper/kanbanStageSla';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import KanbanStageSelect from '../../kanban/KanbanStageSelect.vue';
import KanbanStatusQuickClose from './KanbanStatusQuickClose.vue';
import KanbanTerminalStatusBar from './KanbanTerminalStatusBar.vue';
import KanbanCardPeopleRow from './KanbanCardPeopleRow.vue';
import KanbanConversationCardMenu from './KanbanConversationCardMenu.vue';

const props = defineProps({
  card: { type: Object, required: true },
  board: { type: Object, default: () => ({}) },
  regularStages: { type: Array, default: () => [] },
  assignableUsers: { type: Array, default: () => [] },
  isAssigneesLoading: { type: Boolean, default: false },
  isBusy: { type: Boolean, default: false },
  isHighlighted: { type: Boolean, default: false },
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

// The card payload nests only the board's id and name. The container resolves
// the full board, and that is the one that knows the terminal stages, so it
// wins; the nested copy is only a fallback for a board the list never loaded.
const cardBoard = computed(() =>
  props.board?.id ? props.board : props.card.kanbanBoard || {}
);
const wonStageId = computed(() => Number(cardBoard.value.wonStageId) || null);
const lostStageId = computed(() => Number(cardBoard.value.lostStageId) || null);
const hasTerminals = computed(() => !!wonStageId.value && !!lostStageId.value);
const terminalStages = computed(() => [wonStageId.value, lostStageId.value]);

const cardStage = computed(() => props.card.kanbanStage || {});
const cardId = computed(() => props.card.id);
// The sidebar payload nests the stage instead of sending its id on the card.
const stageId = computed(() =>
  Number(props.card.kanbanStageId ?? cardStage.value.id)
);
const isTerminal = computed(
  () => hasTerminals.value && terminalStages.value.includes(stageId.value)
);

const subject = computed(() => props.card.subject || '');
const priority = computed(() => props.card.priority ?? '');
const dueAt = computed(() => props.card.dueAt ?? null);
const dueDate = computed(() => {
  const empty = { label: '', overdue: false };
  if (!dueAt.value) return empty;

  const date = new Date(dueAt.value);
  if (Number.isNaN(date.getTime())) return empty;

  return {
    label: format(date, 'dd/MM'),
    overdue: differenceInCalendarDays(date, new Date()) < 0,
  };
});

const accountLabelList = computed(() => accountLabels?.value || []);
// Card payloads carry bare titles when the label left the account; resolve
// what we can against the account list.
const resolveLabel = label => {
  if (typeof label !== 'string') return label;

  return (
    accountLabelList.value.find(item => item.title === label) || {
      title: label,
    }
  );
};
const labels = computed(() => (props.card.labels || []).map(resolveLabel));
const labelTitles = computed(() =>
  labels.value.map(label => label.title).filter(Boolean)
);
// Two chips read at a glance in ~254px; the rest collapse into a counter.
const visibleLabels = computed(() => labels.value.slice(0, 2));
const overflowCount = (list, visible) => Math.max(list.length - visible, 0);
const extraLabelCount = computed(() =>
  overflowCount(labels.value, visibleLabels.value.length)
);
const assignees = computed(() => props.card.assignees || []);
const extraAssigneeCount = computed(() => overflowCount(assignees.value, 2));

const cardValue = computed(() => Number(props.card.value) || 0);
const hasValue = computed(() => cardValue.value > 0);
const hasDueDate = computed(() => !!dueAt.value && !isTerminal.value);
const hasPriority = computed(() => !!priority.value);
const hasFacts = computed(
  () => hasValue.value || hasDueDate.value || hasPriority.value
);
const boardName = computed(
  () => cardBoard.value?.name || t('KANBAN.CARD.UNKNOWN_BOARD')
);
const boardReasons = computed(() => cardBoard.value.reasons || []);
const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => cardStage.value.slaHours)
  );

const cardMenuRef = ref(null);
const copyCardId = async () => {
  await copyTextToClipboard(cardId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const showAssignees = () => emit('loadAssignees', props.card);
const openDetails = () => emit('openDetails', props.card);
const openMove = () => emit('openMove', props.card);
const openMenuAt = viewName => cardMenuRef.value?.openAtView(viewName);
const onQuickClose = ({ targetStageId, reasonId }) =>
  emit('changeStatus', props.card, { targetStageId, reasonId });

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
    @keydown.enter.self.prevent="openDetails"
    @keydown.space.self.prevent="openDetails"
  >
    <div class="flex min-w-0 items-center gap-1">
      <p
        data-testid="kanban-conversation-card-subject"
        class="min-w-0 flex-1 cursor-pointer truncate text-sm font-medium text-n-slate-12 hover:text-n-brand"
        :title="subject"
        role="button"
        tabindex="0"
        :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.EDIT_DETAILS')"
        @click.stop="openDetails"
        @keydown="onSubjectKeydown"
      >
        {{ subject }}
      </p>

      <div class="flex flex-shrink-0 items-center gap-0.5">
        <KanbanStatusQuickClose
          v-if="hasTerminals && !isTerminal"
          :won-stage-id="wonStageId"
          :lost-stage-id="lostStageId"
          :reasons="boardReasons"
          :lost-reason-required="Boolean(cardBoard.lostReasonRequired)"
          :disabled="isBusy"
          @close="onQuickClose"
        />

        <KanbanConversationCardMenu
          ref="cardMenuRef"
          :card="card"
          :board="cardBoard"
          :account-labels="accountLabelList"
          :label-titles="labelTitles"
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
    </div>

    <div v-if="isTerminal" class="mt-2 flex min-w-0">
      <KanbanTerminalStatusBar
        :stage-id="stageId"
        :won-stage-id="wonStageId"
        :reasons="boardReasons"
        :reason-id="card.kanbanReasonId ? Number(card.kanbanReasonId) : null"
        :entered-at="card.stageEnteredAt"
        :disabled="isBusy"
        @reopen="emit('changeStatus', card, { reopen: true })"
      />
    </div>

    <div v-else class="mt-2 flex min-w-0 items-center gap-1 text-xs">
      <button
        type="button"
        data-testid="kanban-conversation-card-board"
        class="min-w-0 shrink truncate p-0 text-n-slate-11 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
        :title="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD')"
        :disabled="isBusy"
        @click.stop="openMove"
      >
        {{ boardName }}
      </button>
      <i class="i-lucide-chevron-right size-3 flex-shrink-0 text-n-slate-10" />
      <KanbanStageSelect
        :model-value="stageId"
        :stages="regularStages"
        :current-stage="cardStage"
        :disabled="isBusy"
        class="max-w-[10rem] flex-shrink-0"
        data-testid="kanban-conversation-card-stage"
        @update:model-value="emit('updateStage', card, $event)"
      />
      <span
        v-if="stageTime"
        class="ms-auto inline-flex flex-shrink-0 items-center gap-1"
        :class="stageSlaClasses || 'text-n-slate-10'"
        :title="stageTimeTitle"
        :aria-label="
          stageSlaStatusValue === 'stale'
            ? t('KANBAN.CARD.SLA_STALE')
            : t('CONVERSATION_SIDEBAR.KANBAN.IN_STAGE_FOR', { age: stageTime })
        "
      >
        <i
          v-if="[SLA_WARNING, SLA_STALE].includes(stageSlaStatusValue)"
          class="i-lucide-clock size-3"
        />
        {{ stageTime }}
      </span>
    </div>

    <div
      v-if="hasFacts"
      data-testid="kanban-conversation-card-facts"
      class="mt-1.5 flex min-w-0 items-center gap-3 text-xs"
    >
      <span
        v-if="hasValue"
        data-testid="kanban-conversation-card-value"
        class="font-medium text-n-slate-11"
        :title="formatCurrency(cardValue)"
      >
        {{ formatCompactCurrency(cardValue) }}
      </span>
      <span
        v-if="hasDueDate"
        data-testid="kanban-conversation-card-due-date"
        :class="dueDate.overdue ? 'text-n-ruby-11' : 'text-n-slate-10'"
      >
        {{ dueDate.label }}
      </span>
      <CardPriorityIcon
        v-if="hasPriority"
        :priority="priority"
        class="ms-auto flex-shrink-0 !size-3.5"
      />
    </div>

    <KanbanCardPeopleRow
      v-if="visibleLabels.length || assignees.length"
      :visible-labels="visibleLabels"
      :label-titles="labelTitles"
      :extra-label-count="extraLabelCount"
      :assignees="assignees"
      :extra-assignee-count="extraAssigneeCount"
      :disabled="isBusy"
      @open-view="openMenuAt"
    />
  </article>
</template>
