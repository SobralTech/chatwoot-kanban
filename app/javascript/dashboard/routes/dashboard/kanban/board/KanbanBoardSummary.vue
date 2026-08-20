<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { formatCurrency } from 'dashboard/helper/kanbanCurrency';

const props = defineProps({
  summary: {
    type: Object,
    default: () => ({}),
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  error: {
    type: Boolean,
    default: false,
  },
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);
const { t } = useI18n();

const metricText = metric =>
  t('KANBAN.SUMMARY.COUNT_VALUE', {
    count: metric?.count || 0,
    value: formatCurrency(metric?.value),
  });

const metrics = computed(() => {
  const entries = [
    {
      key: 'open',
      label: t('KANBAN.SUMMARY.OPEN'),
      text: metricText(props.summary.open),
      valueClass: 'text-n-slate-12',
    },
    {
      key: 'won',
      label: t('KANBAN.SUMMARY.WON_MONTH'),
      text: metricText(props.summary.wonThisMonth),
      valueClass: 'text-n-teal-11',
    },
    {
      key: 'lost',
      label: t('KANBAN.SUMMARY.LOST_MONTH'),
      text: metricText(props.summary.lostThisMonth),
      valueClass: 'text-n-ruby-11',
    },
  ];

  // Nothing won this month means there is no average to show.
  if (props.summary.averageTicket) {
    entries.push({
      key: 'average',
      label: t('KANBAN.SUMMARY.AVERAGE_TICKET'),
      text: formatCurrency(props.summary.averageTicket),
      valueClass: 'text-n-slate-12',
    });
  }

  return entries;
});
</script>

<template>
  <section
    class="flex min-h-12 min-w-0 items-center justify-between gap-3 border-b border-n-weak px-4 py-2 md:px-6"
    data-testid="kanban-board-summary"
  >
    <div
      v-if="isCollapsed"
      class="flex min-w-0 flex-1 items-center justify-between gap-3 text-xs text-n-slate-11"
    >
      <span v-if="error" class="truncate text-n-ruby-11">
        {{ t('KANBAN.SUMMARY.ERROR') }}
      </span>
      <button
        type="button"
        class="inline-flex flex-shrink-0 items-center gap-1 rounded-md px-1.5 py-1 text-xs text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        data-testid="kanban-summary-show"
        :aria-label="t('KANBAN.SUMMARY.SHOW')"
        :title="t('KANBAN.SUMMARY.SHOW')"
        @click="emit('toggle')"
      >
        <i class="i-lucide-chevron-down size-3.5" />
        {{ t('KANBAN.SUMMARY.SHOW') }}
      </button>
    </div>

    <template v-else>
      <div
        class="flex min-w-0 flex-1 flex-wrap items-center gap-x-6 gap-y-2"
        :class="{ 'opacity-50': isLoading }"
      >
        <div
          v-for="(metric, index) in metrics"
          :key="metric.key"
          class="min-w-0 flex-col"
          :class="index === 0 ? 'flex' : 'hidden md:flex'"
          :data-testid="`kanban-summary-${metric.key}`"
        >
          <span class="text-xs text-n-slate-11">
            {{ metric.label }}
          </span>
          <span class="text-sm font-semibold" :class="metric.valueClass">
            {{ metric.text }}
          </span>
        </div>
      </div>

      <span v-if="error" class="max-w-56 truncate text-xs text-n-ruby-11">
        {{ t('KANBAN.SUMMARY.ERROR') }}
      </span>
      <button
        type="button"
        class="inline-flex flex-shrink-0 items-center justify-center rounded-md p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        data-testid="kanban-summary-hide"
        :aria-label="t('KANBAN.SUMMARY.HIDE')"
        :title="t('KANBAN.SUMMARY.HIDE')"
        @click="emit('toggle')"
      >
        <i class="i-lucide-chevron-up size-4" />
      </button>
    </template>
  </section>
</template>
