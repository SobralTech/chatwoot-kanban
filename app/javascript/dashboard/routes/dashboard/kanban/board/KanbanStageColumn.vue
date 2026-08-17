<script setup>
import { computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import NextButton from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import KanbanConversationCard from '../KanbanConversationCard.vue';
import KanbanStageMenu from '../KanbanStageMenu.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
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
  isCardDragDisabled: {
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
  'copyStage',
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
  'assignAgent',
  'updateDueDate',
  'loadMore',
  'dragStart',
  'dragChange',
  'dragEnd',
  'updateStageName',
  'updateStageColor',
]);
const { t } = useI18n();

const stageName = computed({
  get: () => props.stageNames[props.stage.id] || '',
  set: value => emit('updateStageName', { stageId: props.stage.id, value }),
});

const stageColor = computed({
  get: () => props.stageColors[props.stage.id] || '',
  set: value => emit('updateStageColor', { stageId: props.stage.id, value }),
});
</script>

<template>
  <section
    :data-stage-id="stage.id"
    class="flex w-64 lg:w-80 flex-shrink-0 flex-col snap-start rounded-lg border bg-n-solid-1"
    :class="[
      editingStageId === stage.id ? 'overflow-visible' : 'overflow-hidden',
      stageAccent(stage)?.border ?? 'border-n-weak',
    ]"
  >
    <header
      class="flex min-h-10 items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
      :class="[
        editingStageId === stage.id ? '' : 'stage-drag-handle cursor-grab',
        stageAccent(stage)?.header,
      ]"
    >
      <OnClickOutside
        v-if="editingStageId === stage.id"
        class="min-w-0 flex-1"
        @trigger="emit('cancelEditingStage')"
      >
        <form
          class="flex min-w-0 w-full items-center gap-2"
          @submit.prevent="emit('updateStage', stage)"
        >
          <ColorPicker
            v-if="!isTerminalStage(stage)"
            v-model="stageColor"
            preview-only
            :aria-label="t('KANBAN.ACTIONS.STAGE_COLOR')"
            data-testid="kanban-stage-color-picker"
            class="flex-shrink-0"
          />
          <input
            :ref="element => setStageNameInput(stage.id, element)"
            v-model="stageName"
            type="text"
            class="reset-base !mb-0 h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
            @keydown.escape.prevent="emit('cancelEditingStage')"
          />
          <NextButton
            type="submit"
            icon="i-lucide-check"
            ghost
            xs
            slate
            class="no-drag"
            :aria-label="t('KANBAN.ACTIONS.SAVE_STAGE')"
            :title="t('KANBAN.ACTIONS.SAVE_STAGE')"
          />
          <NextButton
            icon="i-lucide-x"
            ghost
            xs
            slate
            class="no-drag"
            :aria-label="t('KANBAN.ACTIONS.CANCEL')"
            :title="t('KANBAN.ACTIONS.CANCEL')"
            @click="emit('cancelEditingStage')"
          />
        </form>
      </OnClickOutside>
      <template v-else>
        <div class="flex min-w-0 flex-1 items-center gap-2">
          <span
            class="size-2.5 flex-shrink-0 rounded-full"
            :class="stageAccent(stage)?.dot"
            :style="
              isTerminalStage(stage) ? null : { backgroundColor: stage.color }
            "
            aria-hidden="true"
          />
          <h3
            class="truncate text-sm font-semibold"
            :class="stageAccent(stage)?.title ?? 'text-n-slate-12'"
          >
            {{ stage.name }}
          </h3>
          <span
            class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ stage.cardsCount }}
          </span>
          <span
            v-if="stage.totalValue > 0"
            data-testid="kanban-stage-total-value"
            class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          >
            {{ formatCurrency(stage.totalValue) }}
          </span>
        </div>
        <div class="flex flex-shrink-0 gap-1">
          <KanbanStageMenu
            :stage="stage"
            :stages="stages"
            :boards="boards"
            :won-stage-id="board?.wonStageId"
            :lost-stage-id="board?.lostStageId"
            :is-admin="isAdmin"
            :is-busy="isBusy"
            @add-card="emit('addCard', stage)"
            @edit="emit('editStage', stage)"
            @copy="emit('copyStage', stage, $event)"
            @move="emit('moveStage', stage, $event)"
            @move-cards="emit('moveAllCards', stage, $event)"
            @sort="emit('sortCards', stage, $event)"
            @delete-stage="emit('deleteStage', stage)"
            @delete-cards="emit('deleteAllCards', stage)"
          />
        </div>
      </template>
    </header>

    <div
      :data-stage-scroll-id="stage.id"
      class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-3"
    >
      <Draggable
        :list="stage.cards"
        item-key="id"
        class="flex flex-1 flex-col gap-2 rounded-md"
        :title="
          hasActiveFilters
            ? t('KANBAN.ACTIONS.REORDER_DISABLED_FILTERED')
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
            :stages="stages"
            :assignable-users="assignableUsers"
            :won-stage-id="board?.wonStageId"
            :lost-stage-id="board?.lostStageId"
            :reasons="board?.reasons || []"
            :lost-reason-required="board?.lostReasonRequired"
            @open-conversation-in-new-tab="
              emit('openConversationInNewTab', $event)
            "
            @move-to-stage="
              (cardValue, stageId) =>
                emit('moveCardToStage', cardValue, stageId)
            "
            @assign-agent="
              (cardValue, userId) => emit('assignAgent', cardValue, userId)
            "
            @update-due-date="
              (cardValue, dueDate) => emit('updateDueDate', cardValue, dueDate)
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
      v-if="canAddCardInStageFooter(stage)"
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
