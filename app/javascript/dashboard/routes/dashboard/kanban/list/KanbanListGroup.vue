<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';
import KanbanListRow from './KanbanListRow.vue';

defineProps({
  group: {
    type: Object,
    required: true,
  },
  canAddCard: {
    type: Boolean,
    default: false,
  },
  isLoadingMore: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['openCard', 'addCard', 'loadMore']);

const { t } = useI18n();

const isExpanded = ref(true);
</script>

<template>
  <section
    class="rounded-xl bg-n-solid-2 outline-1 outline outline-n-container"
    :data-group-key="group.key"
  >
    <header class="flex min-w-0 items-center gap-2 px-3 py-2">
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-2 text-left"
        :aria-expanded="isExpanded"
        data-testid="kanban-list-group-toggle"
        @click="isExpanded = !isExpanded"
      >
        <i
          class="size-4 flex-shrink-0 text-n-slate-11"
          :class="
            isExpanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
          "
        />
        <span
          class="size-2.5 flex-shrink-0 rounded-full"
          :style="{ backgroundColor: group.color }"
          aria-hidden="true"
        />
        <h3 class="truncate text-sm font-semibold text-n-slate-12">
          {{ group.name }}
        </h3>
        <span
          data-testid="kanban-list-group-count"
          class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
        >
          {{ group.cardsCount }}
        </span>
        <span
          v-if="group.totalValue > 0"
          data-testid="kanban-list-group-total-value"
          class="flex-shrink-0 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
          :title="formatCurrency(group.totalValue)"
        >
          {{ formatCompactCurrency(group.totalValue) }}
        </span>
      </button>

      <NextButton
        v-if="canAddCard"
        :label="t('KANBAN.LIST.ADD_ITEM')"
        icon="i-lucide-plus"
        variant="faded"
        color="slate"
        size="sm"
        class="flex-shrink-0"
        data-testid="kanban-list-group-add-item"
        @click="emit('addCard', group)"
      />
    </header>

    <div v-show="isExpanded" class="flex flex-col gap-0.5 px-1.5 pb-2">
      <KanbanListRow
        v-for="card in group.cards"
        :key="card.id"
        :card="card"
        @open-details="emit('openCard', $event)"
      />

      <p
        v-if="!group.cards.length"
        class="px-2 py-2 text-sm text-n-slate-10"
        data-testid="kanban-list-group-empty"
      >
        {{ t('KANBAN.LIST.EMPTY_GROUP') }}
      </p>

      <NextButton
        v-if="group.hasMore"
        :label="t('KANBAN.LIST.LOAD_MORE')"
        variant="link"
        color="slate"
        size="sm"
        class="self-start"
        data-testid="kanban-list-group-load-more"
        :is-loading="isLoadingMore"
        @click="emit('loadMore', group.key)"
      />
    </div>
  </section>
</template>
