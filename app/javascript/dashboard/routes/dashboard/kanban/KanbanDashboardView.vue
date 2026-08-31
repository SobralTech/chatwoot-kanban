<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { subMonths } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import KanbanReportsAPI from 'dashboard/api/kanbanReports';
import BarChart from 'shared/components/charts/BarChart.vue';
import DoughnutChart from 'shared/components/charts/DoughnutChart.vue';
import KanbanBoardViewShell from './board/KanbanBoardViewShell.vue';

const { t } = useI18n();
const route = useRoute();

const summary = ref(null);
const report = ref(null);
const isLoadingSummary = ref(false);
const isLoadingReport = ref(false);

const boardId = computed(() => Number(route.params.boardId));
const isEmpty = computed(
  () => !isLoadingSummary.value && summary.value?.visible_cards_count === 0
);
const wonCount = computed(() => summary.value?.won_this_month?.count || 0);
const lostCount = computed(() => summary.value?.lost_this_month?.count || 0);
const winRate = computed(() => {
  const total = wonCount.value + lostCount.value;
  return total ? Math.round((wonCount.value * 10000) / total) / 100 : 0;
});

const visibleStages = computed(
  () => summary.value?.visible_stages_summary || []
);
const topStages = computed(() =>
  [...visibleStages.value]
    .sort((first, second) => second.cards_count - first.cards_count)
    .slice(0, 3)
);
const funnelMaximum = computed(() =>
  Math.max(...visibleStages.value.map(stage => stage.cards_count), 0)
);

const funnelWidth = count => {
  if (!funnelMaximum.value || !count) return 'w-0';

  const ratio = count / funnelMaximum.value;
  if (ratio <= 0.2) return 'w-1/5';
  if (ratio <= 0.4) return 'w-2/5';
  if (ratio <= 0.6) return 'w-3/5';
  if (ratio <= 0.8) return 'w-4/5';
  return 'w-full';
};

const tiles = computed(() => [
  {
    key: 'open',
    label: t('KANBAN.DASHBOARD.TILES.OPEN'),
    value: summary.value?.open?.count || 0,
  },
  {
    key: 'new',
    label: t('KANBAN.DASHBOARD.TILES.NEW_THIS_MONTH'),
    value: summary.value?.new_leads_this_month || 0,
  },
  {
    key: 'agents',
    label: t('KANBAN.DASHBOARD.TILES.ACTIVE_AGENTS'),
    value: summary.value?.active_agents_count || 0,
  },
  {
    key: 'win-rate',
    label: t('KANBAN.DASHBOARD.TILES.WIN_RATE'),
    value: `${winRate.value}%`,
  },
  {
    key: 'value',
    label: t('KANBAN.DASHBOARD.TILES.OPEN_VALUE'),
    value: formatCurrency(summary.value?.open?.value),
  },
  {
    key: 'conversation',
    label: t('KANBAN.DASHBOARD.TILES.WITH_CONVERSATION'),
    value: summary.value?.leads_with_conversation_count || 0,
  },
]);

const wonLostCollection = computed(() => ({
  labels: report.value?.won_lost?.series?.map(row => row.period) || [],
  datasets: [
    {
      label: t('KANBAN.DASHBOARD.CHARTS.WON'),
      backgroundColor: '#12B76A',
      data: report.value?.won_lost?.series?.map(row => row.won) || [],
    },
    {
      label: t('KANBAN.DASHBOARD.CHARTS.LOST'),
      backgroundColor: '#F04438',
      data: report.value?.won_lost?.series?.map(row => row.lost) || [],
    },
  ],
}));

const wonLostOptions = { plugins: { legend: { display: true } } };
const originCollection = computed(() => ({
  labels: [
    t('KANBAN.DASHBOARD.CHARTS.ORIGIN_CONVERSATION'),
    t('KANBAN.DASHBOARD.CHARTS.ORIGIN_MANUAL'),
  ],
  datasets: [
    {
      backgroundColor: ['#7F56D9', '#36BFFA'],
      data: [
        summary.value?.origin_summary?.conversation || 0,
        summary.value?.origin_summary?.manual || 0,
      ],
    },
  ],
}));

const reportParams = () => {
  const now = new Date();
  const since = subMonths(now, 5);
  since.setDate(1);
  since.setHours(0, 0, 0, 0);

  return {
    boardId: boardId.value,
    from: Math.floor(since.getTime() / 1000),
    to: Math.floor(now.getTime() / 1000),
    groupBy: 'month',
  };
};

const fetchSummary = async () => {
  isLoadingSummary.value = true;
  try {
    const response = await KanbanBoardsAPI.getSummary(boardId.value);
    summary.value = response.data;
  } catch (error) {
    useAlert(t('KANBAN.DASHBOARD.ERROR'));
  } finally {
    isLoadingSummary.value = false;
  }
};

const fetchReport = async () => {
  isLoadingReport.value = true;
  try {
    const response = await KanbanReportsAPI.getDashboard(reportParams());
    report.value = response.data;
  } catch (error) {
    useAlert(t('KANBAN.DASHBOARD.ERROR'));
  } finally {
    isLoadingReport.value = false;
  }
};

const fetchDashboard = () => Promise.all([fetchSummary(), fetchReport()]);

onMounted(fetchDashboard);
watch(boardId, fetchDashboard);
</script>

<template>
  <KanbanBoardViewShell>
    <div
      class="min-h-0 flex-1 overflow-y-auto p-4 md:p-6"
      data-testid="kanban-dashboard"
    >
      <div
        v-if="isEmpty"
        class="flex min-h-64 items-center justify-center rounded-xl bg-n-solid-2 p-6 text-sm text-n-slate-11 shadow outline-1 outline outline-n-container"
      >
        {{ t('KANBAN.DASHBOARD.EMPTY') }}
      </div>

      <div v-else class="flex flex-col gap-4">
        <div
          class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4"
          :class="{ 'opacity-50': isLoadingSummary }"
        >
          <section
            v-for="tile in tiles"
            :key="tile.key"
            class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
          >
            <p class="m-0 text-sm text-n-slate-11">{{ tile.label }}</p>
            <p class="mb-0 mt-2 text-2xl font-semibold text-n-slate-12">
              {{ tile.value }}
            </p>
          </section>

          <section
            class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container sm:col-span-2"
          >
            <p class="m-0 text-sm text-n-slate-11">
              {{ t('KANBAN.DASHBOARD.TILES.TOP_STAGES') }}
            </p>
            <div class="mt-2 flex flex-col gap-1">
              <div
                v-for="stage in topStages"
                :key="stage.id"
                class="flex items-center justify-between gap-3 text-sm"
              >
                <span class="truncate text-n-slate-12">{{ stage.name }}</span>
                <span class="font-medium text-n-slate-11">{{
                  stage.cards_count
                }}</span>
              </div>
            </div>
          </section>
        </div>

        <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
          <section
            class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
            :class="{ 'opacity-50': isLoadingReport }"
          >
            <h2 class="mb-4 text-base font-semibold text-n-slate-12">
              {{ t('KANBAN.DASHBOARD.CHARTS.WON_LOST') }}
            </h2>
            <div class="h-72">
              <BarChart
                :collection="wonLostCollection"
                :chart-options="wonLostOptions"
              />
            </div>
          </section>

          <section
            class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
            :class="{ 'opacity-50': isLoadingSummary }"
          >
            <h2 class="mb-4 text-base font-semibold text-n-slate-12">
              {{ t('KANBAN.DASHBOARD.CHARTS.ORIGIN') }}
            </h2>
            <div class="h-72">
              <DoughnutChart :collection="originCollection" />
            </div>
          </section>
        </div>

        <section
          class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
          :class="{ 'opacity-50': isLoadingSummary }"
        >
          <h2 class="mb-4 text-base font-semibold text-n-slate-12">
            {{ t('KANBAN.DASHBOARD.CHARTS.STAGE_FUNNEL') }}
          </h2>
          <div class="flex flex-col gap-3">
            <div
              v-for="stage in visibleStages"
              :key="stage.id"
              class="grid grid-cols-[7rem_1fr_auto] items-center gap-3"
            >
              <span class="truncate text-sm font-medium text-n-slate-12">{{
                stage.name
              }}</span>
              <div class="h-8 rounded-r-lg bg-n-slate-3">
                <div
                  class="h-8 rounded-r-lg bg-n-brand transition-all"
                  :class="funnelWidth(stage.cards_count)"
                />
              </div>
              <span class="text-right text-sm text-n-slate-11">
                {{ stage.cards_count }}
              </span>
            </div>
          </div>
        </section>
      </div>
    </div>
  </KanbanBoardViewShell>
</template>
