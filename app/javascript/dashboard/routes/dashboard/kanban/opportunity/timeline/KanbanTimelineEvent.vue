<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import KanbanTimelineAvatar from './KanbanTimelineAvatar.vue';

const props = defineProps({
  event: { type: Object, required: true },
});

const { t } = useI18n();

const orUnknown = value =>
  value || t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE');

const priorityLabel = priority =>
  t(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`);

const dueDateLabel = dueAt => format(new Date(dueAt), 'dd/MM/yyyy');

const productLabel = metadata => orUnknown(metadata.name || metadata.sku);

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
</script>

<template>
  <div class="flex gap-3">
    <KanbanTimelineAvatar :user="event.user" />
    <div class="min-w-0 flex-1 border-b border-n-weak pb-4">
      <p class="mb-1 text-sm leading-5 text-n-slate-12">
        <span class="font-medium">{{ authorName }}</span>
        {{ message }}
      </p>
      <time class="text-xs text-n-slate-10">{{ timestamp }}</time>
    </div>
  </div>
</template>
