<script setup>
import KanbanCardLabelsRow from './header/KanbanCardLabelsRow.vue';
import KanbanCardQuickControls from './header/KanbanCardQuickControls.vue';
import KanbanCardTitleRow from './header/KanbanCardTitleRow.vue';

defineProps({
  card: {
    type: Object,
    default: null,
  },
  cardDisplayId: {
    type: [Number, String],
    default: null,
  },
  boardName: {
    type: String,
    default: '',
  },
  openedFromConversation: {
    type: Boolean,
    default: false,
  },
  hasUnsavedChanges: {
    type: Boolean,
    default: false,
  },
  isPending: {
    type: Function,
    default: () => false,
  },
  accountLabels: {
    type: Array,
    default: () => [],
  },
  selectedLabelTitles: {
    type: Array,
    default: () => [],
  },
  assignedUsers: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
  totalValue: {
    type: Number,
    default: 0,
  },
  stages: {
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
  reasons: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits([
  'changeStatus',
  'addLabel',
  'removeLabel',
  'toggleAssignee',
  'openProducts',
  'openConversation',
  'openConversationInNewTab',
  'openFunnel',
  'openMove',
  'copyCardId',
  'copyCardLink',
  'removeCard',
  'close',
]);

const subject = defineModel('subject', {
  type: String,
  default: '',
});
const priority = defineModel('priority', {
  type: String,
  default: '',
});
const dueAt = defineModel('dueAt', {
  type: String,
  default: '',
});
</script>

<template>
  <header
    data-testid="kanban-opportunity-header"
    class="flex flex-none flex-col gap-2 border-b border-n-weak px-4 py-3"
  >
    <KanbanCardTitleRow
      v-if="card"
      v-model:subject="subject"
      :card="card"
      :card-display-id="cardDisplayId"
      :board-name="boardName"
      :stages="stages"
      :opened-from-conversation="openedFromConversation"
      :has-unsaved-changes="hasUnsavedChanges"
      :is-pending="isPending('subject')"
      @open-conversation="emit('openConversation', $event)"
      @open-conversation-in-new-tab="emit('openConversationInNewTab', $event)"
      @open-funnel="emit('openFunnel', $event)"
      @copy-card-id="emit('copyCardId')"
      @copy-card-link="emit('copyCardLink', $event)"
      @remove-card="emit('removeCard', $event)"
      @close="emit('close')"
    />
    <KanbanCardQuickControls
      v-if="card"
      v-model:priority="priority"
      v-model:due-at="dueAt"
      :card="card"
      :stages="stages"
      :won-stage-id="wonStageId"
      :lost-stage-id="lostStageId"
      :lost-reason-required="lostReasonRequired"
      :reasons="reasons"
      :total-value="totalValue"
      :assigned-users="assignedUsers"
      :assignable-users="assignableUsers"
      :is-pending="isPending"
      @change-status="emit('changeStatus', $event)"
      @open-move="emit('openMove')"
      @toggle-assignee="emit('toggleAssignee', $event)"
      @open-products="emit('openProducts')"
    />
    <KanbanCardLabelsRow
      v-if="card"
      :account-labels="accountLabels"
      :selected-label-titles="selectedLabelTitles"
      :disabled="isPending('labels')"
      @add-label="emit('addLabel', $event)"
      @remove-label="emit('removeLabel', $event)"
    />
  </header>
</template>
