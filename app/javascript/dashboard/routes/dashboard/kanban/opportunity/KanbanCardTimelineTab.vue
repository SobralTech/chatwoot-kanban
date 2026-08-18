<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
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

const metadataValue = (event, key, fallbackKey) => {
  const metadata = event.metadata || {};
  return (
    metadata[key] ||
    metadata[fallbackKey] ||
    t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE')
  );
};

const stageValue = (metadata, nameKey, idKey) =>
  metadata[nameKey] ||
  metadata[idKey] ||
  t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE');

const eventMessage = event => {
  const metadata = event.metadata || {};

  switch (event.eventType) {
    case 'card_created':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.CARD_CREATED');
    case 'stage_changed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.STAGE_CHANGED', {
        from: stageValue(metadata, 'fromStageName', 'fromStageId'),
        to: stageValue(metadata, 'toStageName', 'toStageId'),
      });
    case 'won':
      if (metadata.reasonTitle) {
        return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.WON', {
          reason: metadata.reasonTitle,
        });
      }
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.WON_NO_REASON');
    case 'lost':
      if (metadata.reasonTitle) {
        return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.LOST', {
          reason: metadata.reasonTitle,
        });
      }
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.LOST_NO_REASON');
    case 'reopened':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.REOPENED');
    case 'priority_changed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.PRIORITY_CHANGED', {
        to: metadataValue(event, 'to'),
      });
    case 'assignees_changed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.ASSIGNEES_CHANGED');
    case 'due_at_changed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.DUE_AT_CHANGED', {
        to: metadataValue(event, 'to'),
      });
    case 'labels_changed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.LABELS_CHANGED');
    case 'product_added':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.PRODUCT_ADDED', {
        quantity: metadata.quantity,
        name: metadata.name || metadata.sku,
      });
    case 'product_removed':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.PRODUCT_REMOVED', {
        name: metadata.name || metadata.sku,
      });
    case 'product_price_changed':
      return t(
        'KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.PRODUCT_PRICE_CHANGED',
        { name: metadata.name || metadata.sku }
      );
    case 'product_quantity_changed':
      return t(
        'KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.PRODUCT_QUANTITY_CHANGED',
        { name: metadata.name || metadata.sku }
      );
    case 'card_deleted':
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.CARD_DELETED');
    default:
      return t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.UNKNOWN');
  }
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
