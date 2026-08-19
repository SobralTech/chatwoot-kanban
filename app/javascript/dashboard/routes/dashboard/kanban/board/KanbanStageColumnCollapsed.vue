<script setup>
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import { formatCurrency } from 'dashboard/helper/kanbanCurrency';

defineProps({
  stage: {
    type: Object,
    required: true,
  },
  headerClass: {
    type: String,
    default: '',
  },
  isCardDragDisabled: {
    type: Boolean,
    default: false,
  },
  sortableOptions: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['toggleCollapse', 'dragChange']);
const { t } = useI18n();
</script>

<template>
  <div
    class="flex min-h-0 flex-1 flex-col items-center gap-2 p-1"
    :class="headerClass"
  >
    <button
      type="button"
      data-testid="kanban-stage-expand"
      class="no-drag flex size-7 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :aria-label="t('KANBAN.STAGE.EXPAND')"
      :title="t('KANBAN.STAGE.EXPAND')"
      @click.stop="emit('toggleCollapse')"
    >
      <i class="i-lucide-chevrons-right-left size-4" />
    </button>
    <span
      class="stage-drag-handle min-h-0 flex-1 cursor-grab select-none truncate text-xs font-semibold text-n-slate-12 [writing-mode:vertical-rl]"
      :title="stage.name"
    >
      {{ stage.name }}
    </span>
    <!-- Drop-only target: the column loads no cards, so the options that govern
    dragging a card out of a list (handle, filter, swap thresholds, ghost and
    chosen classes, animation, start and end) have nothing to act on here. The
    cards it does receive are rendered hidden until the stage refresh clears
    them, and every drop appends because the real order is never loaded. -->
    <Draggable
      :list="stage.cards"
      item-key="id"
      class="min-h-8 w-full flex-1 rounded-md"
      :group="{ name: 'kanban-cards' }"
      :empty-insert-threshold="30"
      v-bind="sortableOptions"
      :disabled="isCardDragDisabled"
      @change="emit('dragChange', stage, $event, { appendToStageEnd: true })"
    >
      <template #item="{ element: card }">
        <span class="hidden" :data-card-id="card.id" />
      </template>
    </Draggable>
    <span
      class="flex-shrink-0 rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[10px] font-semibold text-n-slate-11"
    >
      {{ stage.cardsCount }}
    </span>
    <span
      data-testid="kanban-stage-collapsed-total-value"
      class="flex-shrink-0 rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[10px] font-medium text-n-slate-11"
    >
      {{ formatCurrency(stage.totalValue) }}
    </span>
  </div>
</template>
