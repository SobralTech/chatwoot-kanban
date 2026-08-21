<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  rules: {
    type: Array,
    default: () => [],
  },
  selectedRuleId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const route = useRoute();

const logs = ref([]);
const isLoading = ref(false);
const loadError = ref('');
const expandedIds = ref(new Set());
const filters = ref({
  ruleId: props.selectedRuleId || '',
  status: '',
  period: '7d',
});

const ruleOptions = computed(() => [
  { value: '', label: t('KANBAN.AUTOMATIONS.LOG.ALL_RULES') },
  ...props.rules.map(rule => ({ value: rule.id, label: rule.name })),
]);

const statusOptions = computed(() => [
  { value: '', label: t('KANBAN.AUTOMATIONS.LOG.ALL_STATUSES') },
  {
    value: 'matched',
    label: t('KANBAN.AUTOMATIONS.LOG.STATUS.MATCHED'),
  },
  {
    value: 'executed',
    label: t('KANBAN.AUTOMATIONS.LOG.STATUS.EXECUTED'),
  },
  {
    value: 'simulated',
    label: t('KANBAN.AUTOMATIONS.LOG.STATUS.SIMULATED'),
  },
  { value: 'skipped', label: t('KANBAN.AUTOMATIONS.LOG.STATUS.SKIPPED') },
  { value: 'failed', label: t('KANBAN.AUTOMATIONS.LOG.STATUS.FAILED') },
]);

const statusLabels = computed(() => ({
  matched: t('KANBAN.AUTOMATIONS.LOG.STATUS.MATCHED'),
  executed: t('KANBAN.AUTOMATIONS.LOG.STATUS.EXECUTED'),
  simulated: t('KANBAN.AUTOMATIONS.LOG.STATUS.SIMULATED'),
  skipped: t('KANBAN.AUTOMATIONS.LOG.STATUS.SKIPPED'),
  failed: t('KANBAN.AUTOMATIONS.LOG.STATUS.FAILED'),
}));

const periodOptions = computed(() => [
  { value: '24h', label: t('KANBAN.AUTOMATIONS.LOG.PERIOD.24H') },
  { value: '7d', label: t('KANBAN.AUTOMATIONS.LOG.PERIOD.7D') },
  { value: '30d', label: t('KANBAN.AUTOMATIONS.LOG.PERIOD.30D') },
]);

const ruleName = ruleId =>
  props.rules.find(rule => Number(rule.id) === Number(ruleId))?.name ||
  t('KANBAN.AUTOMATIONS.LOG.UNKNOWN_RULE', { id: ruleId });

const statusClass = status => {
  if (status === 'executed') return 'bg-n-teal-2 text-n-teal-11';
  if (status === 'simulated') return 'bg-n-amber-2 text-n-amber-11';
  if (status === 'failed') return 'bg-n-ruby-2 text-n-ruby-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

const statusLabel = status =>
  statusLabels.value[String(status).toLowerCase()] || status;

const logDate = timestamp =>
  new Intl.DateTimeFormat(undefined, {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(Number(timestamp) * 1000));

const actionDetails = log => log.details?.actions || [];

const actionSummary = log => {
  const actions = actionDetails(log);
  if (!actions.length) return t('KANBAN.AUTOMATIONS.LOG.NO_ACTION_DETAILS');

  return actions
    .map(action =>
      t('KANBAN.AUTOMATIONS.LOG.ACTION_SUMMARY', {
        action: action.action_name,
        status: statusLabel(action.status),
      })
    )
    .join(' · ');
};

const detailText = log => JSON.stringify(log.details || {}, null, 2);

const contentDetails = log =>
  actionDetails(log).flatMap(action => {
    const metadata = action.metadata || {};
    return metadata.content
      ? [{ status: action.status, content: metadata.content }]
      : [];
  });

const skipReasons = log =>
  actionDetails(log).flatMap(action => {
    const reason = action.metadata?.reason;
    return reason ? [reason] : [];
  });

const toggleExpanded = id => {
  const next = new Set(expandedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expandedIds.value = next;
};

const fromForPeriod = period => {
  const durations = {
    '24h': 24 * 60 * 60 * 1000,
    '7d': 7 * 24 * 60 * 60 * 1000,
    '30d': 30 * 24 * 60 * 60 * 1000,
  };
  return new Date(Date.now() - durations[period]).toISOString();
};

const fetchLogs = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const params = {
      from: fromForPeriod(filters.value.period),
      limit: 100,
    };
    if (filters.value.ruleId) params.rule_id = filters.value.ruleId;
    if (filters.value.status) params.status = filters.value.status;

    const response = await KanbanBoardsAPI.getAutomationLogs(
      props.boardId,
      params
    );
    logs.value = response.data?.payload || [];
  } catch (error) {
    loadError.value =
      error?.response?.data?.error ||
      error?.message ||
      t('KANBAN.AUTOMATIONS.LOG.LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const cardLink = cardId => ({
  name: 'kanban_board_show',
  params: {
    accountId: route?.params?.accountId,
    boardId: props.boardId,
  },
  query: { card_id: cardId },
});

watch(
  () => props.selectedRuleId,
  value => {
    filters.value.ruleId = value || '';
  }
);

watch(filters, fetchLogs, { deep: true });
onMounted(fetchLogs);
</script>

<template>
  <section class="grid gap-4" data-testid="kanban-automation-log-list">
    <h2 class="mb-0 text-base font-medium text-n-slate-12">
      {{ t('KANBAN.AUTOMATIONS.LOG.TITLE') }}
    </h2>
    <div
      class="grid gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-3 sm:grid-cols-3"
    >
      <label class="grid gap-1 text-xs font-medium text-n-slate-11">
        {{ t('KANBAN.AUTOMATIONS.LOG.RULE_FILTER') }}
        <Select v-model="filters.ruleId" :options="ruleOptions" full-width />
      </label>
      <label class="grid gap-1 text-xs font-medium text-n-slate-11">
        {{ t('KANBAN.AUTOMATIONS.LOG.STATUS_FILTER') }}
        <Select v-model="filters.status" :options="statusOptions" full-width />
      </label>
      <label class="grid gap-1 text-xs font-medium text-n-slate-11">
        {{ t('KANBAN.AUTOMATIONS.LOG.PERIOD_FILTER') }}
        <Select v-model="filters.period" :options="periodOptions" full-width />
      </label>
    </div>

    <p v-if="isLoading" class="py-8 text-center text-sm text-n-slate-11">
      {{ t('KANBAN.AUTOMATIONS.LOG.LOADING') }}
    </p>
    <p
      v-else-if="loadError"
      class="rounded-md bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>
    <p
      v-else-if="logs.length === 0"
      data-testid="kanban-automation-log-empty"
      class="rounded-md border border-dashed border-n-weak px-3 py-8 text-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.AUTOMATIONS.LOG.EMPTY') }}
    </p>

    <div v-else class="grid gap-2">
      <article
        v-for="log in logs"
        :key="log.id"
        class="grid gap-3 rounded-lg border border-n-weak bg-n-surface-1 p-3"
      >
        <button
          type="button"
          class="grid min-w-0 gap-2 text-left"
          :aria-expanded="expandedIds.has(log.id)"
          @click="toggleExpanded(log.id)"
        >
          <div
            class="flex min-w-0 flex-wrap items-center gap-2 text-xs text-n-slate-10"
          >
            <time>{{ logDate(log.created_at) }}</time>
            <span class="min-w-0 truncate font-medium text-n-slate-12">
              {{ ruleName(log.kanban_automation_rule_id) }}
            </span>
            <span
              class="rounded-full px-2 py-0.5 font-medium"
              :class="statusClass(log.status)"
            >
              {{ statusLabel(log.status) }}
            </span>
            <i
              class="ml-auto size-4"
              :class="
                expandedIds.has(log.id)
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </div>
          <div
            class="flex min-w-0 flex-wrap items-center gap-2 text-sm text-n-slate-12"
          >
            <router-link
              v-if="log.kanban_card_id"
              :to="cardLink(log.kanban_card_id)"
              class="text-n-blue-11 hover:underline"
              @click.stop
            >
              {{ t('KANBAN.AUTOMATIONS.LOG.CARD', { id: log.kanban_card_id }) }}
            </router-link>
            <span v-else>{{ t('KANBAN.AUTOMATIONS.LOG.DELETED_CARD') }}</span>
            <span class="min-w-0 truncate text-xs text-n-slate-11">
              {{ actionSummary(log) }}
            </span>
          </div>
        </button>

        <div
          v-if="expandedIds.has(log.id)"
          class="grid gap-3 border-t border-n-weak pt-3"
        >
          <div v-if="contentDetails(log).length" class="grid gap-2">
            <div
              v-for="(content, index) in contentDetails(log)"
              :key="`${log.id}-content-${index}`"
              class="rounded-md bg-n-alpha-2 p-3"
            >
              <p class="mb-1 text-xs font-medium text-n-slate-11">
                {{
                  content.status === 'simulated'
                    ? t('KANBAN.AUTOMATIONS.LOG.SIMULATED_TEXT')
                    : t('KANBAN.AUTOMATIONS.LOG.SENT_TEXT')
                }}
              </p>
              <p class="mb-0 whitespace-pre-wrap text-sm text-n-slate-12">
                {{ content.content }}
              </p>
            </div>
          </div>
          <p
            v-if="skipReasons(log).length"
            class="mb-0 text-sm text-n-amber-11"
          >
            {{
              t('KANBAN.AUTOMATIONS.LOG.SKIP_REASON', {
                reason: skipReasons(log).join(', '),
              })
            }}
          </p>
          <pre
            class="m-0 overflow-x-auto rounded-md bg-n-slate-2 p-3 text-xs text-n-slate-11"
          >
            {{ detailText(log) }}
          </pre>
        </div>
      </article>
    </div>
  </section>
</template>
