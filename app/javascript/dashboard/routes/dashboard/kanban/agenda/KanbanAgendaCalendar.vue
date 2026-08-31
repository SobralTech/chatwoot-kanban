<script setup>
import { computed } from 'vue';
import { isSameDay, isSameMonth } from 'date-fns';

import { toDayKey } from 'dashboard/composables/useKanbanAgendaData';
import KanbanAgendaDayCell from './KanbanAgendaDayCell.vue';

const props = defineProps({
  weeks: {
    type: Array,
    required: true,
  },
  referenceDate: {
    type: Date,
    required: true,
  },
  cardsByDay: {
    type: Object,
    default: () => ({}),
  },
  stageColors: {
    type: Object,
    default: () => ({}),
  },
  isWeekMode: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['cardClick', 'createNew', 'scheduleExisting']);

const today = new Date();

// Taken from the rendered dates so the weekday headers follow the same locale
// and week start the grid was built with.
const weekdayLabels = computed(() =>
  (props.weeks[0] || []).map(date =>
    date.toLocaleDateString(undefined, { weekday: 'short' })
  )
);

const cardsFor = date => props.cardsByDay[toDayKey(date)] || [];
</script>

<template>
  <div class="min-w-0 overflow-x-auto" data-testid="kanban-agenda-calendar">
    <div class="min-w-[36rem]">
      <div class="grid grid-cols-7 border-l border-t border-n-weak">
        <div
          v-for="label in weekdayLabels"
          :key="label"
          class="truncate border-b border-r border-n-weak bg-n-solid-1 px-2 py-1.5 text-xs font-medium uppercase text-n-slate-11"
        >
          {{ label }}
        </div>
      </div>

      <div
        v-for="(week, weekIndex) in weeks"
        :key="weekIndex"
        class="grid grid-cols-7 border-l border-n-weak"
      >
        <KanbanAgendaDayCell
          v-for="day in week"
          :key="day.toISOString()"
          :date="day"
          :cards="cardsFor(day)"
          :stage-colors="stageColors"
          :max-visible="isWeekMode ? 8 : 3"
          :is-outside-month="!isWeekMode && !isSameMonth(day, referenceDate)"
          :is-today="isSameDay(day, today)"
          :class="isWeekMode ? 'min-h-96' : 'min-h-24'"
          @card-click="emit('cardClick', $event)"
          @create-new="emit('createNew', $event)"
          @schedule-existing="emit('scheduleExisting', $event)"
        />
      </div>
    </div>
  </div>
</template>
