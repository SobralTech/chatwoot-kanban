<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { formatCompactCurrency } from 'dashboard/helper/kanbanCurrency';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import KanbanAgendaCreatePopover from './KanbanAgendaCreatePopover.vue';

const props = defineProps({
  date: {
    type: Date,
    required: true,
  },
  cards: {
    type: Array,
    default: () => [],
  },
  stageColors: {
    type: Object,
    default: () => ({}),
  },
  maxVisible: {
    type: Number,
    default: 3,
  },
  isOutsideMonth: {
    type: Boolean,
    default: false,
  },
  isToday: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['cardClick', 'createNew', 'scheduleExisting']);

const { t } = useI18n();

const isExpanded = ref(false);

const visibleCards = computed(() =>
  isExpanded.value ? props.cards : props.cards.slice(0, props.maxVisible)
);
const hiddenCount = computed(
  () => props.cards.length - visibleCards.value.length
);
const dayTotal = computed(() =>
  props.cards.reduce((total, card) => total + (Number(card.value) || 0), 0)
);

const stageColor = card =>
  props.stageColors[card.kanbanStageId] || DEFAULT_KANBAN_STAGE_COLOR;
const cardTitle = card =>
  card.subject || card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');

const createNewCard = () => {
  emit('createNew', props.date);
};

const scheduleExistingCard = () => {
  emit('scheduleExisting', props.date);
};

// Collapsing again on a month change keeps a tall cell from surviving into a
// day the user never expanded.
watch(
  () => props.date,
  () => {
    isExpanded.value = false;
  }
);
</script>

<template>
  <div
    class="flex min-h-0 flex-col gap-1 border-b border-r border-n-weak p-1.5"
    :class="isOutsideMonth ? 'bg-n-solid-1' : 'bg-n-background'"
    :data-testid="`kanban-agenda-day-${date.getDate()}`"
  >
    <div class="relative flex items-center justify-between gap-1">
      <span
        class="flex size-6 flex-shrink-0 items-center justify-center rounded-full text-xs"
        :class="[
          isToday ? 'bg-n-brand font-semibold text-white' : '',
          isOutsideMonth ? 'text-n-slate-10' : 'text-n-slate-12',
        ]"
      >
        {{ date.getDate() }}
      </span>
      <div class="flex min-w-0 items-center gap-1">
        <span
          v-if="dayTotal > 0"
          class="truncate text-xs text-n-slate-11"
          :title="String(dayTotal)"
        >
          {{ formatCompactCurrency(dayTotal) }}
        </span>
        <KanbanAgendaCreatePopover
          :date="date"
          @create-new="createNewCard"
          @schedule-existing="scheduleExistingCard"
        />
      </div>
    </div>

    <ul class="m-0 flex min-h-0 list-none flex-col gap-1 overflow-y-auto p-0">
      <li v-for="card in visibleCards" :key="card.id">
        <button
          class="flex w-full items-center gap-1.5 rounded-md bg-n-solid-2 px-1.5 py-1 text-left outline-1 outline outline-n-container hover:bg-n-solid-3"
          :title="cardTitle(card)"
          :data-card-id="card.id"
          @click="emit('cardClick', card)"
        >
          <span
            class="size-2 flex-shrink-0 rounded-full"
            :style="{ backgroundColor: stageColor(card) }"
            aria-hidden="true"
          />
          <span class="truncate text-xs text-n-slate-12">
            {{ cardTitle(card) }}
          </span>
        </button>
      </li>
    </ul>

    <button
      v-if="hiddenCount > 0"
      class="text-left text-xs text-n-brand hover:underline"
      @click="isExpanded = true"
    >
      {{ t('KANBAN.AGENDA.MORE_ITEMS', { count: hiddenCount }) }}
    </button>
  </div>
</template>
