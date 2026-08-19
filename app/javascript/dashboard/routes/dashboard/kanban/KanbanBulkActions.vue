<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
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
const selectedAssigneeIds = ref([]);
const selectedLabelTitles = ref([]);

const stageOptions = computed(() =>
  props.stages
    .filter(
      stage =>
        Number(stage.id) !== Number(props.wonStageId) &&
        Number(stage.id) !== Number(props.lostStageId)
    )
    .map(stage => ({
      value: stage.id,
      label: stage.name,
      color: stage.color,
    }))
);

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

const toggleAssignee = userId => {
  const numericUserId = Number(userId);
  const nextSelectedAssigneeIds = new Set(selectedAssigneeIds.value);

  if (nextSelectedAssigneeIds.has(numericUserId)) {
    nextSelectedAssigneeIds.delete(numericUserId);
  } else {
    nextSelectedAssigneeIds.add(numericUserId);
  }

  selectedAssigneeIds.value = [...nextSelectedAssigneeIds];
};

const isAssigneeSelected = userId =>
  selectedAssigneeIds.value.includes(Number(userId));

const assignSelected = hide => {
  if (!selectedAssigneeIds.value.length) return;

  chooseAction('assign', { assignee_ids: selectedAssigneeIds.value }, hide);
};

const toggleLabel = labelTitle => {
  const nextSelectedLabelTitles = new Set(selectedLabelTitles.value);

  if (nextSelectedLabelTitles.has(labelTitle)) {
    nextSelectedLabelTitles.delete(labelTitle);
  } else {
    nextSelectedLabelTitles.add(labelTitle);
  }

  selectedLabelTitles.value = [...nextSelectedLabelTitles];
};

const isLabelSelected = labelTitle =>
  selectedLabelTitles.value.includes(labelTitle);

const applySelectedLabels = hide => {
  if (!selectedLabelTitles.value.length) return;

  chooseAction('label', { labels: selectedLabelTitles.value }, hide);
};

const resetAssigneeSelection = () => {
  selectedAssigneeIds.value = [];
};

const resetLabelSelection = () => {
  selectedLabelTitles.value = [];
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

    <KanbanBulkActionMenu
      :label="t('KANBAN.BULK.MOVE')"
      icon="i-lucide-corner-up-right"
      :options="stageOptions"
      :empty-text="t('KANBAN.CARD.NO_REGULAR_STAGES')"
      trigger-testid="kanban-bulk-action-move"
      option-testid="kanban-bulk-move-stage"
      :is-busy="isBusy"
      @select="chooseAction('move', { kanban_stage_id: $event })"
    >
      <template #optionIcon="{ option }">
        <span
          class="size-2.5 flex-shrink-0 rounded-full bg-n-slate-9"
          :style="{ backgroundColor: option.color }"
        />
      </template>
    </KanbanBulkActionMenu>

    <KanbanBulkActionMenu
      :label="t('KANBAN.BULK.ASSIGN')"
      icon="i-lucide-user-round"
      :options="assigneeOptions"
      :empty-text="t('KANBAN.CARD.NO_ASSIGNABLE_USERS')"
      trigger-testid="kanban-bulk-action-assign"
      option-testid="kanban-bulk-assign-agent"
      :close-on-select="false"
      :is-busy="isBusy"
      @select="toggleAssignee"
      @hide="resetAssigneeSelection"
    >
      <template #optionContent="{ option }">
        <input
          type="checkbox"
          class="pointer-events-none"
          :checked="isAssigneeSelected(option.value)"
          tabindex="-1"
        />
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
          v-if="selectedAssigneeIds.length"
          type="button"
          data-testid="kanban-bulk-assign-submit"
          class="mt-1 flex w-full items-center justify-center gap-2 rounded-md bg-n-brand px-2 py-1.5 text-sm font-medium text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isBusy"
          @click="assignSelected(hide)"
        >
          <i class="i-lucide-user-round-plus size-4" />
          {{ t('KANBAN.BULK.APPLY') }}
        </button>
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
      :close-on-select="false"
      :is-busy="isBusy"
      @select="toggleLabel"
      @hide="resetLabelSelection"
    >
      <template #optionContent="{ option }">
        <input
          type="checkbox"
          class="pointer-events-none"
          :checked="isLabelSelected(option.value)"
          tabindex="-1"
        />
        <WootLabel
          :title="option.label"
          :bg-color="option.color"
          small
          class="!m-0 max-w-full flex-1"
        />
      </template>
      <template #footer="{ hide }">
        <button
          v-if="selectedLabelTitles.length"
          type="button"
          data-testid="kanban-bulk-label-submit"
          class="mt-1 flex w-full items-center justify-center gap-2 rounded-md bg-n-brand px-2 py-1.5 text-sm font-medium text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isBusy"
          @click="applySelectedLabels(hide)"
        >
          <i class="i-lucide-tags size-4" />
          {{ t('KANBAN.BULK.APPLY') }}
        </button>
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
