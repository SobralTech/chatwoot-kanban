<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import { SLA_STALE, SLA_WARNING } from 'dashboard/helper/kanbanStageSla';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import Button from 'dashboard/components-next/button/Button.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import KanbanDueDateBadge from '../../kanban/KanbanDueDateBadge.vue';
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
  'openFunnel',
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

const accountLabelList = computed(() => accountLabels?.value || []);
const labelTitles = computed(() =>
  (props.card.labels || [])
    .map(label => (typeof label === 'string' ? label : label?.title))
    .filter(Boolean)
);
const assignees = computed(() => props.card.assignees || []);
const extraAssigneeCount = computed(() =>
  Math.max(assignees.value.length - 2, 0)
);

const cardValue = computed(() => Number(props.card.value) || 0);
const hasValue = computed(() => cardValue.value > 0);
const hasDueDate = computed(
  () => !!formatDateInput(dueAt.value) && !isTerminal.value
);
const hasPriority = computed(() => !!priority.value);
const boardName = computed(
  () => cardBoard.value?.name || t('KANBAN.CARD.UNKNOWN_BOARD')
);
const boardReasons = computed(() => cardBoard.value.reasons || []);
const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => cardStage.value.slaHours)
  );
const hasStageTime = computed(() => !!stageTime.value && !isTerminal.value);
const hasFacts = computed(
  () =>
    hasValue.value ||
    hasDueDate.value ||
    hasStageTime.value ||
    hasPriority.value
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
          @open-funnel="emit('openFunnel', card)"
          @open-move="openMove"
          @update-priority="value => emit('updatePriority', card, value)"
          @update-due-date="value => emit('updateDueDate', card, value)"
          @update-labels="titles => emit('updateLabels', card, titles)"
          @update-assignees="ids => emit('updateAssignees', card, ids)"
        />
      </div>
    </div>

    <div class="mt-2 grid min-w-0 gap-2">
      <div class="grid min-w-0 gap-1">
        <span
          data-testid="kanban-conversation-card-board-label"
          class="text-xs font-medium text-n-slate-11"
        >
          {{ t('CONVERSATION_SIDEBAR.KANBAN.BOARD') }}
        </span>
        <Button
          data-testid="kanban-conversation-card-board"
          variant="outline"
          color="slate"
          justify="start"
          class="w-full"
          :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD')"
          :title="boardName"
          :disabled="isBusy"
          @click.stop="openMove"
        >
          <i class="i-lucide-corner-up-right size-4 flex-shrink-0" />
          <span class="min-w-0 flex-1 truncate text-left">
            {{ boardName }}
          </span>
        </Button>
      </div>

      <div class="grid min-w-0 gap-1">
        <span
          data-testid="kanban-conversation-card-stage-label"
          class="text-xs font-medium text-n-slate-11"
        >
          {{ t('CONVERSATION_SIDEBAR.KANBAN.STAGE') }}
        </span>
        <KanbanStageSelect
          v-if="!isTerminal"
          :model-value="stageId"
          :stages="regularStages"
          :current-stage="cardStage"
          :disabled="isBusy"
          data-testid="kanban-conversation-card-stage"
          @update:model-value="emit('updateStage', card, $event)"
        />

        <KanbanTerminalStatusBar
          v-else
          :stage-id="stageId"
          :won-stage-id="wonStageId"
          :reasons="boardReasons"
          :reason-id="card.kanbanReasonId ? Number(card.kanbanReasonId) : null"
          :entered-at="card.stageEnteredAt"
          :disabled="isBusy"
          @reopen="emit('changeStatus', card, { reopen: true })"
        />
      </div>
    </div>

    <div
      v-if="hasFacts"
      data-testid="kanban-conversation-card-facts"
      class="mt-2 flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 text-xs"
    >
      <span
        v-if="hasValue"
        data-testid="kanban-conversation-card-value"
        class="font-medium text-n-slate-11"
        :title="formatCurrency(cardValue)"
      >
        {{ formatCompactCurrency(cardValue) }}
      </span>
      <KanbanDueDateBadge
        v-if="hasDueDate"
        data-testid="kanban-conversation-card-due-date"
        :due-at="dueAt"
      />
      <span
        v-if="hasStageTime"
        class="inline-flex flex-shrink-0 items-center gap-1"
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
      <CardPriorityIcon
        v-if="hasPriority"
        :priority="priority"
        class="flex-shrink-0 !size-3.5"
      />
    </div>

    <KanbanCardPeopleRow
      v-if="labelTitles.length || assignees.length"
      :label-titles="labelTitles"
      :assignees="assignees"
      :extra-assignee-count="extraAssigneeCount"
      :disabled="isBusy"
      @open-view="openMenuAt"
    />
  </article>
</template>
