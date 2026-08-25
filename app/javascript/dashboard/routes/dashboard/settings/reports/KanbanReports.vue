<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { subDays } from 'date-fns';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { getUnixEndOfDay, getUnixStartOfDay } from 'helpers/DateHelper';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import ReportHeader from './components/ReportHeader.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import KanbanReportTable from './components/KanbanReportTable.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import KanbanReportsAPI from 'dashboard/api/kanbanReports';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const labels = useMapGetter('labels/getLabels');

const boards = ref([]);
const dashboard = ref(null);
const selectedBoardId = ref(null);
const customDateRange = ref([subDays(new Date(), 29), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_30_DAYS);
const groupBy = ref('day');
const selectedAgents = ref([]);
const selectedInboxes = ref([]);
const selectedLabels = ref([]);
const isLoading = ref(false);
const error = ref('');
const downloadingReport = ref('');
const initialized = ref(false);

const groupByOptions = computed(() => [
  { value: 'day', label: t('REPORT.KANBAN.FILTERS.DAY') },
  { value: 'week', label: t('REPORT.KANBAN.FILTERS.WEEK') },
]);

const boardOptions = computed(() =>
  boards.value.map(board => ({ value: board.id, label: board.name }))
);

const selectedBoardLabel = computed(
  () =>
    boardOptions.value.find(option => option.value === selectedBoardId.value)
      ?.label || t('REPORT.KANBAN.FILTERS.BOARD')
);

const agentOptions = computed(() =>
  agents.value.map(agent => ({
    id: agent.id,
    name: agent.available_name || agent.name,
  }))
);

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ id: inbox.id, name: inbox.name }))
);

const labelOptions = computed(() =>
  labels.value.map(label => ({ id: label.title, name: label.title }))
);

const report = computed(() => dashboard.value || {});
const summary = computed(() => report.value.summary || {});
const conversion = computed(() => report.value.conversion || []);
const stageTimes = computed(() => report.value.stage_times || []);
const wonLost = computed(() => report.value.won_lost || { series: [] });
const lossReasons = computed(() => report.value.loss_reasons || []);
const agentRows = computed(() => report.value.agents || []);
const productRows = computed(() => report.value.products || []);

const metricCards = computed(() => [
  {
    key: 'open',
    label: t('REPORT.KANBAN.SUMMARY.OPEN'),
    value: String(summary.value.open?.count ?? 0),
  },
  {
    key: 'won',
    label: t('REPORT.KANBAN.SUMMARY.WON'),
    value: String(summary.value.won?.count ?? 0),
  },
  {
    key: 'lost',
    label: t('REPORT.KANBAN.SUMMARY.LOST'),
    value: String(summary.value.lost?.count ?? 0),
  },
  {
    key: 'average_ticket',
    label: t('REPORT.KANBAN.SUMMARY.AVERAGE_TICKET'),
    value: summary.value.average_ticket || '0.00',
  },
  {
    key: 'conversion_rate',
    label: t('REPORT.KANBAN.SUMMARY.CONVERSION'),
    value: `${summary.value.conversion_rate || 0}%`,
  },
]);

const chartCollection = computed(() => ({
  labels: wonLost.value.series?.map(row => row.period) || [],
  datasets: [
    {
      label: t('REPORT.KANBAN.CHART.WON'),
      backgroundColor: '#12B76A',
      data: wonLost.value.series?.map(row => row.won) || [],
    },
    {
      label: t('REPORT.KANBAN.CHART.LOST'),
      backgroundColor: '#F04438',
      data: wonLost.value.series?.map(row => row.lost) || [],
    },
  ],
}));

const chartOptions = computed(() => ({
  plugins: {
    legend: { display: true },
  },
  scales: {
    x: {
      title: {
        display: true,
        text: t('REPORT.KANBAN.CHART.X_AXIS'),
      },
    },
    y: {
      beginAtZero: true,
      title: {
        display: true,
        text: t('REPORT.KANBAN.CHART.Y_AXIS'),
      },
    },
  },
}));

const funnelMaximum = computed(() =>
  Math.max(...conversion.value.map(stage => stage.count), 0)
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

const formatDuration = seconds => {
  if (!seconds) return t('REPORT.KANBAN.TABLE.NO_DURATION');
  if (seconds < 60)
    return t('REPORT.KANBAN.TABLE.SECONDS', { value: Math.round(seconds) });
  if (seconds < 3600)
    return t('REPORT.KANBAN.TABLE.MINUTES', {
      value: Math.round(seconds / 60),
    });

  return t('REPORT.KANBAN.TABLE.HOURS', { value: (seconds / 3600).toFixed(1) });
};

const stageTimeRows = computed(() =>
  stageTimes.value.map(row => ({
    ...row,
    average_seconds: formatDuration(row.average_seconds),
    median_seconds: formatDuration(row.median_seconds),
  }))
);

const conversionColumns = computed(() => [
  { key: 'stage_name', label: t('REPORT.KANBAN.TABLE.HEADERS.STAGE') },
  { key: 'count', label: t('REPORT.KANBAN.TABLE.HEADERS.COUNT') },
  {
    key: 'conversion_rate',
    label: t('REPORT.KANBAN.TABLE.HEADERS.CONVERSION'),
  },
]);

const stageTimeColumns = computed(() => [
  { key: 'stage_name', label: t('REPORT.KANBAN.TABLE.HEADERS.STAGE') },
  {
    key: 'average_seconds',
    label: t('REPORT.KANBAN.TABLE.HEADERS.AVERAGE_TIME'),
  },
  {
    key: 'median_seconds',
    label: t('REPORT.KANBAN.TABLE.HEADERS.MEDIAN_TIME'),
  },
  { key: 'completed_count', label: t('REPORT.KANBAN.TABLE.HEADERS.COMPLETED') },
]);

const reasonColumns = computed(() => [
  { key: 'reason_title', label: t('REPORT.KANBAN.TABLE.HEADERS.REASON') },
  { key: 'count', label: t('REPORT.KANBAN.TABLE.HEADERS.COUNT') },
  { key: 'percentage', label: t('REPORT.KANBAN.TABLE.HEADERS.PERCENTAGE') },
]);

const agentColumns = computed(() => [
  { key: 'agent_name', label: t('REPORT.KANBAN.TABLE.HEADERS.AGENT') },
  { key: 'won', label: t('REPORT.KANBAN.TABLE.HEADERS.WON') },
  { key: 'lost', label: t('REPORT.KANBAN.TABLE.HEADERS.LOST') },
  {
    key: 'conversion_rate',
    label: t('REPORT.KANBAN.TABLE.HEADERS.CONVERSION'),
  },
  { key: 'revenue', label: t('REPORT.KANBAN.TABLE.HEADERS.REVENUE') },
]);

const productColumns = computed(() => [
  { key: 'sku', label: t('REPORT.KANBAN.TABLE.HEADERS.SKU') },
  { key: 'product_name', label: t('REPORT.KANBAN.TABLE.HEADERS.PRODUCT') },
  { key: 'quantity', label: t('REPORT.KANBAN.TABLE.HEADERS.QUANTITY') },
  { key: 'revenue', label: t('REPORT.KANBAN.TABLE.HEADERS.REVENUE') },
  { key: 'cards_count', label: t('REPORT.KANBAN.TABLE.HEADERS.CARDS') },
]);

const queryArray = value => {
  const values = Array.isArray(value) ? value : [value];
  return values
    .filter(item => item !== undefined && item !== null && item !== '')
    .flatMap(item => String(item).split(','));
};

const queryIds = value => queryArray(value).map(Number).filter(Boolean);

const initializeFromUrl = () => {
  const query = route.query;
  const boardId = Number(query.kanban_board_id);
  if (boardId) selectedBoardId.value = boardId;
  if (query.group_by === 'day' || query.group_by === 'week')
    groupBy.value = query.group_by;
  if (query.from && query.to) {
    customDateRange.value = [
      new Date(Number(query.from) * 1000),
      new Date(Number(query.to) * 1000),
    ];
    selectedDateRange.value = DATE_RANGE_TYPES.CUSTOM_RANGE;
  }

  selectedAgents.value = queryIds(query.agent_ids).map(id => ({
    id,
    name: String(id),
  }));
  selectedInboxes.value = queryIds(query.inbox_ids).map(id => ({
    id,
    name: String(id),
  }));
  selectedLabels.value = queryArray(query.labels).map(label => ({
    id: label,
    name: label,
  }));
};

const requestParams = () => ({
  boardId: selectedBoardId.value,
  from: getUnixStartOfDay(customDateRange.value[0]),
  to: getUnixEndOfDay(customDateRange.value[1]),
  groupBy: groupBy.value,
  businessHours: false,
  agentIds: selectedAgents.value.map(agent => agent.id),
  inboxIds: selectedInboxes.value.map(inbox => inbox.id),
  labels: selectedLabels.value.map(label => label.id),
});

const onDateRangeChange = ([start, end, rangeType]) => {
  customDateRange.value = [start, end];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
};

const updateUrl = () => {
  const params = {
    ...route.query,
    kanban_board_id: selectedBoardId.value || undefined,
    from: getUnixStartOfDay(customDateRange.value[0]),
    to: getUnixEndOfDay(customDateRange.value[1]),
    group_by: groupBy.value,
    agent_ids:
      selectedAgents.value.map(agent => agent.id).join(',') || undefined,
    inbox_ids:
      selectedInboxes.value.map(inbox => inbox.id).join(',') || undefined,
    labels: selectedLabels.value.map(label => label.id).join(',') || undefined,
  };

  router.replace({ query: params });
};

const fetchDashboard = async () => {
  if (!selectedBoardId.value) {
    dashboard.value = null;
    return;
  }

  isLoading.value = true;
  error.value = '';
  try {
    const response = await KanbanReportsAPI.getDashboard(requestParams());
    dashboard.value = response.data;
  } catch (requestError) {
    error.value = t('REPORT.KANBAN.STATES.ERROR');
    useAlert(error.value);
  } finally {
    isLoading.value = false;
  }
};

const loadBoards = async () => {
  const response = await KanbanReportsAPI.getDashboard();
  boards.value = response.data.boards || [];

  if (!boards.value.length) return;

  const routeBoardId = selectedBoardId.value;
  selectedBoardId.value = boards.value.some(board => board.id === routeBoardId)
    ? routeBoardId
    : boards.value[0].id;
};

const loadFilterOptions = () => {
  store.dispatch('agents/get');
  store.dispatch('inboxes/get');
  store.dispatch('labels/get');
};

const downloadReport = async reportName => {
  downloadingReport.value = reportName;
  try {
    const response = await KanbanReportsAPI.getCsv(reportName, requestParams());
    downloadCsvFile(`kanban-${reportName}.csv`, response.data);
  } catch (requestError) {
    useAlert(t('REPORT.KANBAN.STATES.DOWNLOAD_ERROR'));
  } finally {
    downloadingReport.value = '';
  }
};

onMounted(async () => {
  initializeFromUrl();
  loadFilterOptions();
  try {
    await loadBoards();
    initialized.value = true;
    updateUrl();
    await fetchDashboard();
  } catch (requestError) {
    error.value = t('REPORT.KANBAN.STATES.ERROR');
    useAlert(error.value);
    initialized.value = true;
  }
});

watch(
  [
    selectedBoardId,
    groupBy,
    customDateRange,
    selectedAgents,
    selectedInboxes,
    selectedLabels,
  ],
  async () => {
    if (!initialized.value) return;
    updateUrl();
    await fetchDashboard();
  },
  { deep: true }
);
</script>

<template>
  <ReportHeader
    :header-title="$t('REPORT.KANBAN.HEADER')"
    :header-description="$t('REPORT.KANBAN.DESCRIPTION')"
  />

  <div class="flex flex-col gap-5 pb-10">
    <section
      class="flex flex-wrap items-center gap-2 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
    >
      <FilterSelect
        v-model="selectedBoardId"
        :options="boardOptions"
        :label="selectedBoardLabel"
      />
      <WootDatePicker
        v-model:date-range="customDateRange"
        v-model:range-type="selectedDateRange"
        @date-range-changed="onDateRangeChange"
      />
      <FilterSelect
        v-model="groupBy"
        :options="groupByOptions"
        :label="$t('REPORT.KANBAN.FILTERS.GROUP_BY')"
      />
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-11">
          {{ $t('REPORT.KANBAN.FILTERS.AGENTS') }}
        </span>
        <MultiSelect
          v-model="selectedAgents"
          :options="agentOptions"
          :max-chips="2"
        />
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-11">
          {{ $t('REPORT.KANBAN.FILTERS.INBOXES') }}
        </span>
        <MultiSelect
          v-model="selectedInboxes"
          :options="inboxOptions"
          :max-chips="2"
        />
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-11">
          {{ $t('REPORT.KANBAN.FILTERS.LABELS') }}
        </span>
        <MultiSelect
          v-model="selectedLabels"
          :options="labelOptions"
          :max-chips="2"
        />
      </div>
    </section>

    <EmptyState
      v-if="!isLoading && !boards.length"
      :title="$t('REPORT.KANBAN.STATES.NO_BOARD')"
      :message="$t('REPORT.KANBAN.STATES.NO_BOARD_DESCRIPTION')"
    />
    <p
      v-else-if="error"
      class="m-0 rounded-xl bg-n-ruby-2 p-8 text-center text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <template v-else>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
        <ReportMetricCard
          v-for="metric in metricCards"
          :key="metric.key"
          :label="metric.label"
          :value="metric.value"
          :info-text="$t('REPORT.KANBAN.SUMMARY.INFO')"
          :disabled="isLoading"
        />
      </div>

      <section
        class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      >
        <div class="mb-4 flex items-center justify-between gap-3">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            {{ $t('REPORT.KANBAN.CHART.TITLE') }}
          </h2>
          <Button
            :label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
            icon="i-ph-download-simple"
            size="sm"
            variant="outline"
            color="slate"
            :is-loading="downloadingReport === 'won_lost'"
            :disabled="isLoading || downloadingReport === 'won_lost'"
            @click="downloadReport('won_lost')"
          />
        </div>
        <div
          v-if="isLoading"
          class="flex h-72 items-center justify-center gap-2"
        >
          <span class="text-sm text-n-slate-11">{{
            $t('REPORT.KANBAN.STATES.LOADING')
          }}</span>
        </div>
        <div
          v-else-if="!wonLost.series?.length"
          class="flex h-72 items-center justify-center text-sm text-n-slate-10"
        >
          {{ $t('REPORT.KANBAN.STATES.NO_DATA') }}
        </div>
        <div v-else class="h-72">
          <BarChart
            :collection="chartCollection"
            :chart-options="chartOptions"
          />
        </div>
      </section>

      <section
        class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      >
        <h2 class="mb-4 text-base font-semibold text-n-slate-12">
          {{ $t('REPORT.KANBAN.FUNNEL.TITLE') }}
        </h2>
        <div
          v-if="!conversion.length"
          class="py-8 text-center text-sm text-n-slate-10"
        >
          {{ $t('REPORT.KANBAN.STATES.NO_DATA') }}
        </div>
        <div v-else class="flex flex-col gap-3">
          <div
            v-for="stage in conversion"
            :key="stage.stage_id"
            class="grid grid-cols-[7rem_1fr_auto] items-center gap-3"
          >
            <span class="truncate text-sm font-medium text-n-slate-12">{{
              stage.stage_name
            }}</span>
            <div class="h-8 rounded-r-lg bg-n-slate-3">
              <div
                class="h-8 rounded-r-lg bg-n-brand transition-all"
                :class="funnelWidth(stage.count)"
              />
            </div>
            <span class="text-right text-sm text-n-slate-11">
              {{
                $t('REPORT.KANBAN.FUNNEL.VALUE', {
                  count: stage.count,
                  conversion: stage.conversion_rate,
                })
              }}
            </span>
          </div>
        </div>
      </section>

      <KanbanReportTable
        :title="$t('REPORT.KANBAN.TABLE.TITLES.CONVERSION')"
        :rows="conversion"
        :columns="conversionColumns"
        :loading="isLoading"
        :error="error"
        :empty-message="$t('REPORT.KANBAN.STATES.NO_DATA')"
        :download-label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
        :download-loading="downloadingReport === 'conversion'"
        @download="downloadReport('conversion')"
      />
      <KanbanReportTable
        :title="$t('REPORT.KANBAN.TABLE.TITLES.STAGE_TIMES')"
        :rows="stageTimeRows"
        :columns="stageTimeColumns"
        :loading="isLoading"
        :error="error"
        :empty-message="$t('REPORT.KANBAN.STATES.NO_DATA')"
        :download-label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
        :download-loading="downloadingReport === 'stage_times'"
        @download="downloadReport('stage_times')"
      />
      <KanbanReportTable
        :title="$t('REPORT.KANBAN.TABLE.TITLES.REASONS')"
        :rows="lossReasons"
        :columns="reasonColumns"
        :loading="isLoading"
        :error="error"
        :empty-message="$t('REPORT.KANBAN.STATES.NO_DATA')"
        :download-label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
        :download-loading="downloadingReport === 'loss_reasons'"
        @download="downloadReport('loss_reasons')"
      />
      <KanbanReportTable
        :title="$t('REPORT.KANBAN.TABLE.TITLES.AGENTS')"
        :rows="agentRows"
        :columns="agentColumns"
        :loading="isLoading"
        :error="error"
        :empty-message="$t('REPORT.KANBAN.STATES.NO_DATA')"
        :download-label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
        :download-loading="downloadingReport === 'agents'"
        @download="downloadReport('agents')"
      />
      <KanbanReportTable
        :title="$t('REPORT.KANBAN.TABLE.TITLES.PRODUCTS')"
        :rows="productRows"
        :columns="productColumns"
        :loading="isLoading"
        :error="error"
        :empty-message="$t('REPORT.KANBAN.STATES.NO_DATA')"
        :download-label="$t('REPORT.KANBAN.TABLE.DOWNLOAD')"
        :download-loading="downloadingReport === 'products'"
        @download="downloadReport('products')"
      />
    </template>
  </div>
</template>
