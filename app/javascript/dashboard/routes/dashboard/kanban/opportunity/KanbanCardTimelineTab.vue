<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import camelcaseKeys from 'camelcase-keys';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
  cardId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const events = ref([]);
const hasMore = ref(false);
const nextCursor = ref(null);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const loadError = ref('');

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.message || fallback;

const loadEvents = async (loadMore = false) => {
  if (loadMore) {
    isLoadingMore.value = true;
  } else {
    isLoading.value = true;
    loadError.value = '';
  }

  try {
    const response = await KanbanBoardsAPI.getCardEvents(
      props.boardId,
      props.cardId,
      loadMore && nextCursor.value ? { before_id: nextCursor.value } : {}
    );
    const payload = camelcaseKeys(response.data || {}, { deep: true });
    const fetchedEvents = payload.payload || [];

    events.value = loadMore
      ? [...events.value, ...fetchedEvents]
      : fetchedEvents;
    hasMore.value = !!payload.hasMore;
    nextCursor.value = payload.nextCursor;
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_ERROR')
    );
    if (!loadMore) useAlert(loadError.value);
  } finally {
    isLoading.value = false;
    isLoadingMore.value = false;
  }
};

const orUnknown = value =>
  value || t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE');

const priorityLabel = priority =>
  t(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`);

const dueDateLabel = dueAt => format(new Date(dueAt), 'dd/MM/yyyy');

const productLabel = metadata => orUnknown(metadata.name || metadata.sku);

// Each builder maps the event metadata to the message key it needs, under
// TIMELINE.EVENTS, plus the interpolation params for that key.
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

const eventMessage = event => {
  const buildMessage = EVENT_MESSAGES[event.eventType];
  const [key, params = {}] = buildMessage
    ? buildMessage(event.metadata || {})
    : ['UNKNOWN'];

  return t(`KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.${key}`, params);
};

const eventTimestamp = event =>
  shortTimestamp(dynamicTime(event.createdAt), true);

onMounted(() => loadEvents());
</script>

<template>
  <section
    data-testid="kanban-opportunity-timeline-tab"
    class="grid min-w-0 gap-4"
  >
    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.TITLE') }}
    </h3>
    <p
      v-if="isLoading"
      data-testid="kanban-opportunity-timeline-loading"
      class="mb-0 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOADING') }}
    </p>

    <p
      v-else-if="loadError"
      data-testid="kanban-opportunity-timeline-load-error"
      class="mb-0 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>

    <p
      v-else-if="events.length === 0"
      data-testid="kanban-opportunity-timeline-empty"
      class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EMPTY') }}
    </p>

    <ol
      v-else
      class="grid gap-5"
      data-testid="kanban-opportunity-timeline-list"
    >
      <li
        v-for="event in events"
        :key="event.id"
        class="flex gap-3"
        data-testid="kanban-opportunity-timeline-event"
      >
        <div class="flex size-8 flex-none items-center justify-center">
          <Avatar
            v-if="event.user"
            :name="event.user.name"
            :src="event.user.avatarUrl"
            :size="28"
            rounded-full
          />
          <span
            v-else
            class="flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
            :title="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')"
          >
            <i class="i-lucide-settings size-4" />
          </span>
        </div>
        <div class="min-w-0 flex-1 border-b border-n-weak pb-4">
          <p class="mb-1 text-sm leading-5 text-n-slate-12">
            <span class="font-medium">
              {{
                event.user?.name ||
                t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')
              }}
            </span>
            {{ eventMessage(event) }}
          </p>
          <time class="text-xs text-n-slate-10">
            {{ eventTimestamp(event) }}
          </time>
        </div>
      </li>
    </ol>

    <button
      v-if="hasMore && !loadError"
      type="button"
      class="mx-auto rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-50"
      data-testid="kanban-opportunity-timeline-load-more"
      :disabled="isLoadingMore"
      @click="loadEvents(true)"
    >
      {{
        isLoadingMore
          ? t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOADING')
          : t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_MORE')
      }}
    </button>
  </section>
</template>
