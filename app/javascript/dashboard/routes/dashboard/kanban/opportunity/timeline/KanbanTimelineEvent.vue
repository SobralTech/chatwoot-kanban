<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { format } from 'date-fns';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import KanbanTimelineAvatar from './KanbanTimelineAvatar.vue';

const props = defineProps({
  event: { type: Object, required: true },
  boardId: { type: [Number, String], default: null },
});
const automationRuleNames = new Map();
const automationRuleRequests = new Map();

const { t } = useI18n();
const route = useRoute();

const orUnknown = value =>
  value || t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE');

const priorityLabel = priority =>
  t(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`);

const dueDateLabel = dueAt => format(new Date(dueAt), 'dd/MM/yyyy');

const productLabel = metadata => orUnknown(metadata.name || metadata.sku);

const automationActionMessage = status => {
  if (status === 'skipped') return 'AUTOMATION_ACTION_SKIPPED';
  if (status === 'failed') return 'AUTOMATION_ACTION_FAILED';

  return 'AUTOMATION_ACTION';
};

// Each entry turns the event metadata into an i18n key plus its interpolation params.
const EVENT_MESSAGES = {
  card_created: () => ['CARD_CREATED'],
  card_deleted: () => ['CARD_DELETED'],
  reopened: () => ['REOPENED'],
  assignees_changed: () => ['ASSIGNEES_CHANGED'],
  labels_changed: () => ['LABELS_CHANGED'],
  stage_changed: metadata => [
    'STAGE_CHANGED',
    {
      from: orUnknown(metadata.fromStageName || metadata.fromStageId),
      to: orUnknown(metadata.toStageName || metadata.toStageId),
    },
  ],
  board_changed: metadata => [
    'BOARD_CHANGED',
    {
      fromBoard: orUnknown(metadata.fromBoardName || metadata.fromBoardId),
      fromStage: orUnknown(metadata.fromStageName || metadata.fromStageId),
      toBoard: orUnknown(metadata.toBoardName || metadata.toBoardId),
      toStage: orUnknown(metadata.toStageName || metadata.toStageId),
    },
  ],
  won: metadata =>
    metadata.reasonTitle
      ? ['WON', { reason: metadata.reasonTitle }]
      : ['WON_NO_REASON'],
  lost: metadata =>
    metadata.reasonTitle
      ? ['LOST', { reason: metadata.reasonTitle }]
      : ['LOST_NO_REASON'],
  priority_changed: metadata =>
    metadata.to
      ? ['PRIORITY_CHANGED', { to: priorityLabel(metadata.to) }]
      : ['PRIORITY_CLEARED'],
  due_at_changed: metadata =>
    metadata.to
      ? ['DUE_AT_CHANGED', { to: dueDateLabel(metadata.to) }]
      : ['DUE_AT_CLEARED'],
  product_added: metadata => [
    'PRODUCT_ADDED',
    { quantity: metadata.quantity, name: productLabel(metadata) },
  ],
  product_removed: metadata => [
    'PRODUCT_REMOVED',
    { name: productLabel(metadata) },
  ],
  product_price_changed: metadata => [
    'PRODUCT_PRICE_CHANGED',
    { name: productLabel(metadata) },
  ],
  product_quantity_changed: metadata => [
    'PRODUCT_QUANTITY_CHANGED',
    { name: productLabel(metadata) },
  ],
  automation_action: metadata => [
    automationActionMessage(metadata.status),
    { action: metadata.actionName || metadata.action_name || 'unknown' },
  ],
};

const message = computed(() => {
  const buildMessage = EVENT_MESSAGES[props.event.eventType];
  const [key, params = {}] = buildMessage
    ? buildMessage(props.event.metadata || {})
    : ['UNKNOWN'];

  return t(`KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.${key}`, params);
});

const authorName = computed(
  () =>
    props.event.user?.name ||
    t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')
);

const timestamp = computed(() =>
  shortTimestamp(dynamicTime(props.event.createdAt), true)
);

const isAutomationEvent = computed(
  () => props.event.eventType === 'automation_action'
);

const fetchedAutomationRuleName = ref('');

const automationRuleId = computed(() => {
  const metadata = props.event.metadata || {};
  return metadata.automationRuleId || metadata.automation_rule_id;
});

const loadAutomationRuleName = async () => {
  if (!isAutomationEvent.value || !props.boardId || !automationRuleId.value) {
    return;
  }

  const accountId = route?.params?.accountId;
  const cacheKey = `${accountId}:${props.boardId}:${automationRuleId.value}`;
  if (automationRuleNames.has(cacheKey)) {
    fetchedAutomationRuleName.value = automationRuleNames.get(cacheKey);
    return;
  }

  const requestKey = `${accountId}:${props.boardId}`;
  let request = automationRuleRequests.get(requestKey);
  if (!request) {
    request = KanbanBoardsAPI.getAutomationRules(props.boardId)
      .then(response => response.data?.payload || [])
      .then(rules => {
        rules.forEach(rule => {
          automationRuleNames.set(
            `${accountId}:${props.boardId}:${rule.id}`,
            rule.name
          );
        });
        return rules;
      })
      .finally(() => {
        automationRuleRequests.delete(requestKey);
      });
    automationRuleRequests.set(requestKey, request);
  }

  try {
    await request;
    fetchedAutomationRuleName.value = automationRuleNames.get(cacheKey) || '';
  } catch {
    fetchedAutomationRuleName.value = '';
  }
};

const automationRuleLabel = computed(() => {
  const metadata = props.event.metadata || {};
  return (
    metadata.automationRuleName ||
    metadata.automation_rule_name ||
    fetchedAutomationRuleName.value ||
    t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.AUTOMATION_RULE', {
      id: automationRuleId.value,
    })
  );
});

const automationLogLink = computed(() => ({
  name: 'kanban_board_edit_form',
  params: {
    accountId: route?.params?.accountId,
    boardId: props.boardId,
  },
  query: {
    automation_log: '1',
    automation_rule_id: automationRuleId.value,
  },
}));

onMounted(loadAutomationRuleName);
</script>

<template>
  <div class="flex gap-3">
    <div
      v-if="isAutomationEvent"
      class="flex size-8 flex-none items-center justify-center rounded-full bg-n-blue-2 text-n-blue-11"
      :title="
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.AUTOMATION_RULE', {
          id: automationRuleId,
        })
      "
    >
      <i class="i-lucide-zap size-4" />
    </div>
    <KanbanTimelineAvatar v-else :user="event.user" />
    <div class="min-w-0 flex-1 border-b border-n-weak pb-4">
      <p class="mb-1 text-sm leading-5 text-n-slate-12">
        <span class="font-medium">{{ authorName }}</span>
        <template v-if="isAutomationEvent">
          <router-link
            v-if="automationRuleId && boardId"
            :to="automationLogLink"
            class="font-medium text-n-blue-11 hover:underline"
          >
            {{ automationRuleLabel }}
          </router-link>
          <span v-else>{{ automationRuleLabel }}</span>
          {{ message }}
        </template>
        <template v-else>{{ message }}</template>
      </p>
      <time class="text-xs text-n-slate-10">{{ timestamp }}</time>
    </div>
  </div>
</template>
