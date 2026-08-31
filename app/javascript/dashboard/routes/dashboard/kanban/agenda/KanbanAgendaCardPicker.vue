<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { debounce } from '@chatwoot/utils';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  boardId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'scheduled']);

const { t } = useI18n();
const query = ref('');
const cards = ref([]);
const isSearching = ref(false);
const searchFailed = ref(false);
const schedulingCardId = ref(null);
const searchGeneration = ref(0);

const hasQuery = computed(() => query.value.trim().length >= 2);

const fetchAllPages = async (searchQuery, cursor) => {
  const response = await KanbanBoardsAPI.getBoardCards(props.boardId, {
    q: searchQuery,
    card_statuses: ['open'],
    limit: 50,
    cursor,
  });
  const data = response.data;
  const pageCards = camelcaseKeys(data.cards || [], { deep: true });
  const nextCursor = data.pagination?.next_cursor;

  return nextCursor
    ? [...pageCards, ...(await fetchAllPages(searchQuery, nextCursor))]
    : pageCards;
};

const searchCards = async () => {
  const searchQuery = query.value.trim();
  searchGeneration.value += 1;
  const generation = searchGeneration.value;

  if (searchQuery.length < 2) {
    cards.value = [];
    isSearching.value = false;
    return;
  }

  isSearching.value = true;
  searchFailed.value = false;
  try {
    const results = await fetchAllPages(searchQuery);
    if (generation === searchGeneration.value) cards.value = results;
  } catch (error) {
    if (generation === searchGeneration.value) {
      cards.value = [];
      searchFailed.value = true;
    }
  } finally {
    if (generation === searchGeneration.value) isSearching.value = false;
  }
};

const debouncedSearchCards = debounce(searchCards, 300, false);

watch(query, () => debouncedSearchCards());

const scheduleCard = card => {
  schedulingCardId.value = card.id;
  emit('scheduled', card);
};

const cardTitle = card =>
  card.subject || card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');

onUnmounted(() => {
  searchGeneration.value += 1;
});
</script>

<template>
  <div
    class="overflow-hidden rounded-lg border border-n-weak bg-n-surface-2"
    data-testid="kanban-agenda-card-picker"
  >
    <header
      class="flex items-center justify-between border-b border-n-weak px-5 py-4"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t('KANBAN.AGENDA.ADD_POPOVER.SCHEDULE_EXISTING') }}
      </h3>
      <NextButton
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        size="sm"
        :aria-label="t('KANBAN.AGENDA.CLOSE')"
        @click="emit('close')"
      />
    </header>

    <div class="flex max-h-[32rem] flex-col gap-3 p-5">
      <input
        v-model="query"
        type="search"
        autofocus
        class="min-h-10 w-full rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
        :placeholder="t('KANBAN.AGENDA.ADD_POPOVER.SEARCH_PLACEHOLDER')"
        data-testid="kanban-agenda-card-search"
      />

      <p v-if="isSearching" class="mb-0 text-sm text-n-slate-11">
        {{ t('KANBAN.AGENDA.SEARCHING') }}
      </p>
      <p v-else-if="searchFailed" class="mb-0 text-sm text-n-ruby-11">
        {{ t('KANBAN.AGENDA.SEARCH_ERROR') }}
      </p>
      <p
        v-else-if="hasQuery && !cards.length"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.AGENDA.NO_SEARCH_RESULTS') }}
      </p>

      <ul v-else class="m-0 flex list-none flex-col gap-1 overflow-y-auto p-0">
        <li v-for="card in cards" :key="card.id">
          <button
            type="button"
            class="flex w-full min-w-0 items-center gap-3 rounded-md px-3 py-2 text-left hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="schedulingCardId !== null"
            :data-card-id="card.id"
            @click="scheduleCard(card)"
          >
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ cardTitle(card) }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT') }}
              </span>
            </span>
            <i
              v-if="schedulingCardId === card.id"
              class="i-lucide-loader-circle size-4 animate-spin text-n-slate-11"
            />
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>
