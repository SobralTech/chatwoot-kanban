<script setup>
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import KanbanConversationCard from '../KanbanConversationCard.vue';
import KanbanStageColumnCollapsed from './KanbanStageColumnCollapsed.vue';
import KanbanStageHeader from './KanbanStageHeader.vue';

defineProps({
  stage: {
    type: Object,
    required: true,
  },
  collapsed: {
    type: Boolean,
    default: false,
  },
  terminalPeriod: {
    type: String,
    default: '30d',
  },
  terminalPeriodOptions: {
    type: Array,
    default: () => [],
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  stages: {
    type: Array,
    default: () => [],
  },
  boards: {
    type: Array,
    default: () => [],
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
  suppressNextClick: {
    type: Boolean,
    default: false,
  },
  isCardDragDisabled: {
    type: Boolean,
    default: false,
  },
  selectedCardIds: {
    type: Object,
    default: () => new Set(),
  },
  isSelectionMode: {
    type: Boolean,
    default: false,
  },
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
  highlightedCardId: {
    type: [Number, String],
    default: null,
  },
  sortableOptions: {
    type: Object,
    default: () => ({}),
  },
  cardsError: {
    type: String,
    default: '',
  },
  isLoadingCards: {
    type: Boolean,
    default: false,
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
  interactiveDragFilter: {
    type: String,
    required: true,
  },
  isCardBusy: {
    type: Function,
    required: true,
  },
  isTerminalStage: {
    type: Function,
    required: true,
  },
  stageAccent: {
    type: Function,
    required: true,
  },
  canAddCardInEmptyStage: {
    type: Function,
    required: true,
  },
  canAddCardInStageFooter: {
    type: Function,
    required: true,
  },
  emptyCardsLabel: {
    type: String,
    required: true,
  },
  editingStageId: {
    type: [Number, String],
    default: null,
  },
  stageNames: {
    type: Object,
    default: () => ({}),
  },
  stageColors: {
    type: Object,
    default: () => ({}),
  },
  setStageNameInput: {
    type: Function,
    required: true,
  },
});

const emit = defineEmits([
  'addCard',
  'editStage',
  'updateStage',
  'cancelEditingStage',
  'moveStage',
  'moveAllCards',
  'sortCards',
  'deleteStage',
  'deleteAllCards',
  'openCard',
  'openConversation',
  'openConversationInNewTab',
  'removeCard',
  'updatePriority',
  'changeStatus',
  'moveCardToStage',
  'moveCardToBoard',
  'assignAgent',
  'updateDueDate',
  'updateLabels',
  'toggleSelect',
  'loadMore',
  'dragStart',
  'dragChange',
  'dragEnd',
  'updateStageName',
  'updateStageColor',
  'toggleCollapse',
  'updateTerminalPeriod',
]);
const { t } = useI18n();
</script>

<template>
  <section
    :data-stage-id="stage.id"
    class="flex flex-shrink-0 flex-col snap-start rounded-lg border bg-n-solid-1"
    :class="[
      collapsed
        ? 'w-12 overflow-hidden'
        : editingStageId === stage.id
          ? 'w-64 overflow-visible lg:w-80'
          : 'w-64 overflow-hidden lg:w-80',
      stageAccent(stage)?.border ?? 'border-n-weak',
    ]"
  >
    <KanbanStageColumnCollapsed
      v-if="collapsed"
      :stage="stage"
      :header-class="stageAccent(stage)?.header"
      :is-card-drag-disabled="isCardDragDisabled"
      :sortable-options="sortableOptions"
      :is-terminal-stage="isTerminalStage"
      :stage-accent="stageAccent"
      @toggle-collapse="emit('toggleCollapse')"
      @drag-change="(...args) => emit('dragChange', ...args)"
    />
    <KanbanStageHeader
      v-else
      :stage="stage"
      :board="board"
      :stages="stages"
      :boards="boards"
      :is-admin="isAdmin"
      :is-busy="isBusy"
      :suppress-next-click="suppressNextClick"
      :editing-stage-id="editingStageId"
      :stage-names="stageNames"
      :stage-colors="stageColors"
      :set-stage-name-input="setStageNameInput"
      :is-terminal-stage="isTerminalStage"
      :stage-accent="stageAccent"
      :terminal-period="terminalPeriod"
      :terminal-period-options="terminalPeriodOptions"
      @update-stage-name="emit('updateStageName', $event)"
      @update-stage-color="emit('updateStageColor', $event)"
      @update-stage="emit('updateStage', $event)"
      @cancel-editing-stage="emit('cancelEditingStage')"
      @add-card="emit('addCard', $event)"
      @edit-stage="emit('editStage', $event)"
      @move-stage="(...args) => emit('moveStage', ...args)"
      @move-all-cards="(...args) => emit('moveAllCards', ...args)"
      @sort-cards="(...args) => emit('sortCards', ...args)"
      @delete-stage="emit('deleteStage', $event)"
      @delete-all-cards="emit('deleteAllCards', $event)"
      @toggle-collapse="emit('toggleCollapse')"
      @update-terminal-period="emit('updateTerminalPeriod', $event)"
    />

    <div
      v-if="!collapsed"
      :data-stage-scroll-id="stage.id"
      class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3"
    >
      <Draggable
        :list="stage.cards"
        item-key="id"
        class="flex flex-1 flex-col gap-2 rounded-md"
        :title="
          hasActiveFilters
            ? t('KANBAN.ACTIONS.REORDER_ANCHORED_HINT')
            : undefined
        "
        :group="{ name: 'kanban-cards' }"
        handle=".card-drag-handle"
        :filter="interactiveDragFilter"
        :prevent-on-filter="false"
        :empty-insert-threshold="30"
        :swap-threshold="0.65"
        :inverted-swap-threshold="1"
        v-bind="sortableOptions"
        :disabled="isCardDragDisabled"
        ghost-class="opacity-60"
        chosen-class="opacity-90"
        :animation="150"
        @start="emit('dragStart')"
        @change="emit('dragChange', stage, $event)"
        @end="emit('dragEnd')"
      >
        <template #item="{ element: card }">
          <KanbanConversationCard
            :class="{
              'ring-2 ring-n-brand': card.id === highlightedCardId,
            }"
            :card="card"
            :is-busy="isCardBusy(card, stage)"
            :board="board"
            :boards="boards"
            :is-selected="selectedCardIds.has(card.id)"
            :is-selection-mode="isSelectionMode"
            :is-admin="isAdmin"
            :stages="stages"
            :assignable-users="assignableUsers"
            :won-stage-id="board?.wonStageId"
            :lost-stage-id="board?.lostStageId"
            :sla-hours="stage.slaHours"
            :reasons="board?.reasons || []"
            :lost-reason-required="board?.lostReasonRequired"
            @open-conversation-in-new-tab="
              emit('openConversationInNewTab', $event)
            "
            @move-to-stage="
              (cardValue, stageId) =>
                emit('moveCardToStage', cardValue, stageId)
            "
            @move-to-board="
              (cardValue, payload) =>
                emit('moveCardToBoard', cardValue, payload)
            "
            @assign-agent="
              (cardValue, userId) => emit('assignAgent', cardValue, userId)
            "
            @update-due-date="
              (cardValue, dueDate) => emit('updateDueDate', cardValue, dueDate)
            "
            @update-labels="
              (cardValue, labelTitles) =>
                emit('updateLabels', cardValue, labelTitles)
            "
            @open-details="emit('openCard', card)"
            @open-conversation="
              (cardValue, event) => emit('openConversation', cardValue, event)
            "
            @remove-card="emit('removeCard', card)"
            @update-priority="
              (cardValue, priority) =>
                emit('updatePriority', cardValue, priority)
            "
            @change-status="
              (cardValue, payload) => emit('changeStatus', cardValue, payload)
            "
            @toggle-select="
              (cardValue, event) => emit('toggleSelect', cardValue, event)
            "
          />
        </template>
        <template #footer>
          <template v-if="stage.cards.length === 0">
            <button
              v-if="canAddCardInEmptyStage(stage)"
              type="button"
              data-testid="kanban-empty-stage-add-card"
              :data-stage-id="stage.id"
              class="flex min-h-24 w-full flex-col items-center justify-center gap-2 rounded-md border border-dashed border-n-weak px-3 py-6 text-sm font-medium text-n-slate-11 hover:border-n-brand hover:bg-n-alpha-1 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="isBusy"
              @click="emit('addCard', stage)"
            >
              <i class="i-lucide-plus size-5" />
              {{ t('KANBAN.ACTIONS.ADD_FIRST_CARD') }}
            </button>
            <p
              v-else
              class="pointer-events-none px-1 py-2 text-sm text-n-slate-10"
            >
              {{ emptyCardsLabel }}
            </p>
          </template>
        </template>
      </Draggable>

      <div v-if="cardsError" class="text-sm text-n-ruby-11">
        {{ cardsError }}
      </div>

      <button
        v-if="stage.pagination?.hasMore"
        type="button"
        data-testid="kanban-load-more-cards"
        :data-stage-id="stage.id"
        class="no-drag flex w-full items-center justify-center gap-1 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:enabled:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="isLoadingCards"
        @click="emit('loadMore', stage)"
      >
        <i
          v-if="isLoadingCards"
          class="i-lucide-loader-2 size-4 animate-spin"
        />
        <span v-else>{{ t('KANBAN.ACTIONS.LOAD_MORE_CARDS') }}</span>
      </button>
    </div>

    <div
      v-if="!collapsed && canAddCardInStageFooter(stage)"
      class="border-t border-n-weak p-2"
    >
      <button
        type="button"
        data-testid="kanban-stage-add-card"
        :data-stage-id="stage.id"
        class="flex w-full items-center gap-2 rounded-md px-2 py-2 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="isBusy"
        @click="emit('addCard', stage)"
      >
        <i class="i-lucide-plus size-4" />
        {{ t('KANBAN.STAGE_MENU.ADD_CARD') }}
      </button>
    </div>
  </section>
</template>
