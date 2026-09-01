<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { isSameMonth, parseISO } from 'date-fns';

import NextButton from 'dashboard/components-next/button/Button.vue';
import { toDayKey } from 'dashboard/composables/useKanbanAgendaData';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { useLocale } from 'shared/composables/useLocale';

const props = defineProps({
  cardsByDay: {
    type: Object,
    default: () => ({}),
  },
  cardsWithoutDate: {
    type: Array,
    default: () => [],
  },
  withoutDateCount: {
    type: Number,
    default: 0,
  },
  hasMoreWithoutDate: {
    type: Boolean,
    default: false,
  },
  isLoadingWithoutDate: {
    type: Boolean,
    default: false,
  },
  todayCards: {
    type: Array,
    default: () => [],
  },
  referenceDate: {
    type: Date,
    required: true,
  },
  selectedDate: {
    type: Date,
    default: null,
  },
  currentUserId: {
    type: Number,
    default: null,
  },
  stageColors: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['cardClick', 'loadMore', 'openList']);

const { t } = useI18n();
const { resolvedLocale } = useLocale();

const isNoDateListOpen = ref(false);

const toggleNoDateList = () => {
  isNoDateListOpen.value = !isNoDateListOpen.value;
  if (isNoDateListOpen.value) emit('openList');
};

const mineCount = cards =>
  cards.filter(card =>
    (card.assignees || []).some(assignee => assignee.id === props.currentUserId)
  ).length;

const myItemsToday = computed(() => mineCount(props.todayCards));

const selectedDayCards = computed(() =>
  props.selectedDate ? props.cardsByDay[toDayKey(props.selectedDate)] || [] : []
);

// Only the days of the month the header shows count: the grid also renders the
// tail of the neighbouring months, and those cards are not part of this month.
const monthDayCounts = computed(() =>
  Object.entries(props.cardsByDay)
    .map(([key, cards]) => ({ date: parseISO(key), count: cards.length }))
    .filter(day => day.count > 0 && isSameMonth(day.date, props.referenceDate))
);

const busiestDay = computed(() =>
  monthDayCounts.value.reduce(
    (busiest, day) => (!busiest || day.count > busiest.count ? day : busiest),
    null
  )
);

const quietestDay = computed(() =>
  monthDayCounts.value.reduce(
    (quietest, day) =>
      !quietest || day.count < quietest.count ? day : quietest,
    null
  )
);

const formatDay = date =>
  date.toLocaleDateString(resolvedLocale.value, {
    day: 'numeric',
    month: 'short',
  });

const cardTitle = card =>
  card.subject || card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');
</script>

<template>
  <aside
    class="flex w-full flex-shrink-0 flex-col gap-3 xl:w-72"
    data-testid="kanban-agenda-sidebar"
  >
    <section
      class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      data-testid="kanban-agenda-no-date"
    >
      <button
        type="button"
        class="flex w-full items-center justify-between gap-2 text-sm font-medium text-n-slate-12"
        @click="toggleNoDateList"
      >
        <span class="flex items-center gap-2">
          <span>{{ t('KANBAN.AGENDA.NO_DATE_ITEMS') }}</span>
          <span
            class="rounded-full bg-n-alpha-2 px-2 text-xs text-n-slate-11"
            data-testid="kanban-agenda-no-date-count"
          >
            {{ withoutDateCount }}
          </span>
        </span>
        <i
          class="size-4"
          :class="
            isNoDateListOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
          "
        />
      </button>

      <div
        v-if="isNoDateListOpen"
        class="mt-3 flex max-h-64 flex-col gap-1 overflow-y-auto"
      >
        <p
          v-if="isLoadingWithoutDate && !cardsWithoutDate.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('KANBAN.AGENDA.LOADING_NO_DATE') }}
        </p>

        <button
          v-for="card in cardsWithoutDate"
          :key="card.id"
          type="button"
          class="flex items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          :data-card-id="card.id"
          @click="emit('cardClick', card)"
        >
          <span
            class="size-2 flex-shrink-0 rounded-full"
            :style="{
              backgroundColor:
                stageColors[card.kanbanStageId] || DEFAULT_KANBAN_STAGE_COLOR,
            }"
            aria-hidden="true"
          />
          <span class="truncate text-sm text-n-slate-12">
            {{ cardTitle(card) }}
          </span>
        </button>

        <NextButton
          v-if="hasMoreWithoutDate"
          :label="t('KANBAN.AGENDA.LOAD_MORE')"
          variant="link"
          color="slate"
          size="sm"
          :is-loading="isLoadingWithoutDate"
          class="self-start"
          @click="emit('loadMore')"
        />
      </div>
    </section>

    <section
      class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      data-testid="kanban-agenda-my-items-today"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.AGENDA.MY_ITEMS_TODAY') }}
      </span>
      <p class="mt-1 text-2xl font-semibold text-n-slate-12">
        {{ myItemsToday }}
      </p>
    </section>

    <section
      class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      data-testid="kanban-agenda-day-summary"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.AGENDA.DAY_SUMMARY') }}
      </span>
      <p v-if="!selectedDate" class="mt-1 text-sm text-n-slate-11">
        {{ t('KANBAN.AGENDA.DAY_SUMMARY_EMPTY') }}
      </p>
      <template v-else>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ formatDay(selectedDate) }}
        </p>
        <p class="mt-1 text-2xl font-semibold text-n-slate-12">
          {{ selectedDayCards.length }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{
            t('KANBAN.AGENDA.DAY_SUMMARY_MINE', {
              count: mineCount(selectedDayCards),
            })
          }}
        </p>
      </template>
    </section>

    <section
      class="rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
      data-testid="kanban-agenda-extreme-days"
    >
      <div class="flex flex-col gap-3">
        <div>
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.AGENDA.BUSIEST_DAY') }}
          </span>
          <p
            class="mt-1 text-sm text-n-slate-11"
            data-testid="kanban-agenda-busiest-day"
          >
            {{
              busiestDay
                ? t('KANBAN.AGENDA.DAY_WITH_COUNT', {
                    date: formatDay(busiestDay.date),
                    count: busiestDay.count,
                  })
                : t('KANBAN.AGENDA.NO_ITEMS_MONTH')
            }}
          </p>
        </div>
        <div>
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.AGENDA.QUIETEST_DAY') }}
          </span>
          <p
            class="mt-1 text-sm text-n-slate-11"
            data-testid="kanban-agenda-quietest-day"
          >
            {{
              quietestDay
                ? t('KANBAN.AGENDA.DAY_WITH_COUNT', {
                    date: formatDay(quietestDay.date),
                    count: quietestDay.count,
                  })
                : t('KANBAN.AGENDA.NO_ITEMS_MONTH')
            }}
          </p>
        </div>
      </div>
    </section>
  </aside>
</template>
