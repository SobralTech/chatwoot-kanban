<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  selectedCount: {
    type: Number,
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
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

const regularStages = computed(() =>
  props.stages.filter(
    stage =>
      Number(stage.id) !== Number(props.wonStageId) &&
      Number(stage.id) !== Number(props.lostStageId)
  )
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

const labelOptions = computed(() =>
  props.labels
    .map(label => ({
      value: label.title || label.name,
      label: label.title || label.name,
    }))
    .filter(option => option.value)
);

const reasonOptions = computed(() => {
  const options = props.reasons
    .filter(reason => (reason.reasonType || reason.reason_type) === 'lost')
    .map(reason => ({ value: reason.id, label: reason.title }));

  if (props.lostReasonRequired) return options;

  return [
    { value: '', label: t('KANBAN.CARD.STATUS.REASON_PLACEHOLDER') },
    ...options,
  ];
});

const chooseAction = (action, payload, hide) => {
  emit('action', { action, payload });
  hide?.();
};

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

const actionButtonClasses =
  'inline-flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50';
const menuClasses =
  'w-64 max-w-[calc(100vw-2rem)] rounded-xl border border-n-strong bg-n-alpha-3 p-2 text-sm text-n-slate-12 shadow-lg backdrop-blur';
</script>

<template>
  <div
    v-show="selectedCount"
    data-testid="kanban-bulk-actions"
    class="fixed bottom-4 left-1/2 z-30 flex max-w-[calc(100vw-2rem)] -translate-x-1/2 flex-wrap items-center justify-center gap-1 rounded-xl border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur"
  >
    <span
      data-testid="kanban-bulk-selected-count"
      class="px-2 text-xs font-semibold text-n-slate-12"
    >
      {{ t('KANBAN.BULK.SELECTED', { count: selectedCount }) }}
    </span>

    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-bulk-action-move"
        :class="actionButtonClasses"
        :disabled="isBusy"
      >
        <i class="i-lucide-corner-up-right size-4" />
        {{ t('KANBAN.BULK.MOVE') }}
      </button>
      <template #content="{ hide }">
        <div :class="menuClasses">
          <p
            v-if="!regularStages.length"
            class="px-2 py-1 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.CARD.NO_REGULAR_STAGES') }}
          </p>
          <button
            v-for="stage in regularStages"
            :key="stage.id"
            type="button"
            data-testid="kanban-bulk-move-stage"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2"
            @click="chooseAction('move', { kanban_stage_id: stage.id }, hide)"
          >
            <span class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9" />
            <span class="truncate">{{ stage.name }}</span>
          </button>
        </div>
      </template>
    </Popover>

    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-bulk-action-assign"
        :class="actionButtonClasses"
        :disabled="isBusy"
      >
        <i class="i-lucide-user-round size-4" />
        {{ t('KANBAN.BULK.ASSIGN') }}
      </button>
      <template #content="{ hide }">
        <div :class="menuClasses">
          <p
            v-if="!assignableUsers.length"
            class="px-2 py-1 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.CARD.NO_ASSIGNABLE_USERS') }}
          </p>
          <button
            v-for="user in assignableUsers"
            :key="user.id"
            type="button"
            data-testid="kanban-bulk-assign-agent"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2"
            @click="chooseAction('assign', { assignee_ids: [user.id] }, hide)"
          >
            <span class="min-w-0 flex-1 truncate">{{
              user.name || user.email
            }}</span>
          </button>
          <button
            type="button"
            data-testid="kanban-bulk-unassign"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-11 hover:bg-n-alpha-2"
            @click="chooseAction('assign', { assignee_ids: [] }, hide)"
          >
            <i class="i-lucide-user-round-x size-4" />
            {{ t('KANBAN.BULK.UNASSIGN') }}
          </button>
        </div>
      </template>
    </Popover>

    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-bulk-action-label"
        :class="actionButtonClasses"
        :disabled="isBusy"
      >
        <i class="i-lucide-tag size-4" />
        {{ t('KANBAN.BULK.LABEL') }}
      </button>
      <template #content="{ hide }">
        <div :class="menuClasses">
          <p
            v-if="!labelOptions.length"
            class="px-2 py-1 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.BULK.NO_LABELS') }}
          </p>
          <button
            v-for="label in labelOptions"
            :key="label.value"
            type="button"
            data-testid="kanban-bulk-label-option"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2"
            @click="chooseAction('label', { label: label.value }, hide)"
          >
            <i class="i-lucide-tag size-4" />
            <span class="truncate">{{ label.label }}</span>
          </button>
        </div>
      </template>
    </Popover>

    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-bulk-action-priority"
        :class="actionButtonClasses"
        :disabled="isBusy"
      >
        <i class="i-lucide-signal size-4" />
        {{ t('KANBAN.BULK.PRIORITY') }}
      </button>
      <template #content="{ hide }">
        <div :class="menuClasses">
          <button
            v-for="option in priorityOptions"
            :key="option.value"
            type="button"
            data-testid="kanban-bulk-priority-option"
            class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2"
            @click="
              chooseAction('priority', { priority: option.value || null }, hide)
            "
          >
            <CardPriorityIcon
              :priority="option.value"
              show-empty
              class="size-4"
            />
            <span class="truncate">{{ option.label }}</span>
          </button>
        </div>
      </template>
    </Popover>

    <Popover align="start" disable-mobile-view @hide="resetReason">
      <button
        type="button"
        data-testid="kanban-bulk-action-lose"
        :class="actionButtonClasses"
        :disabled="isBusy"
      >
        <i class="i-lucide-x-circle size-4 text-n-ruby-11" />
        {{ t('KANBAN.BULK.LOSE') }}
      </button>
      <template #content="{ hide }">
        <div :class="menuClasses">
          <label class="grid gap-1 text-xs font-medium text-n-slate-12">
            {{ t('KANBAN.CARD.STATUS.REASON_LABEL') }}
            <Select
              v-model="selectedReasonId"
              data-testid="kanban-bulk-loss-reason"
              :options="reasonOptions"
            />
          </label>
          <p
            v-if="lostReasonRequired && !selectedReasonId"
            class="mt-2 text-xs text-n-ruby-11"
          >
            {{ t('KANBAN.BULK.REASON_REQUIRED') }}
          </p>
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
      :class="`${actionButtonClasses} text-n-ruby-11 hover:bg-n-ruby-2`"
      :disabled="isBusy"
      @click="emit('delete')"
    >
      <i class="i-lucide-trash size-4" />
      {{ t('KANBAN.BULK.DELETE') }}
    </button>

    <button
      type="button"
      data-testid="kanban-bulk-clear"
      class="rounded-md p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :aria-label="t('KANBAN.BULK.CLEAR')"
      :title="t('KANBAN.BULK.CLEAR')"
      @click="emit('clear')"
    >
      <i class="i-lucide-x size-4" />
    </button>

    <p class="basis-full text-center text-[11px] text-n-slate-10">
      {{ t('KANBAN.BULK.SELECTION_VOLATILE') }}
    </p>
  </div>
</template>
