<script setup>
import { computed } from 'vue';
import { differenceInCalendarDays } from 'date-fns';

import { formatDateInput } from 'dashboard/helper/kanbanDueDate';

const props = defineProps({
  dueAt: {
    type: [String, Number, Date],
    default: null,
  },
});

const dueDate = computed(() => {
  const dateValue = formatDateInput(props.dueAt);
  if (!dateValue) return null;

  const [year, month, day] = dateValue.split('-').map(Number);
  return new Date(year, month - 1, day);
});
const dueDateLabel = computed(() =>
  formatDateInput(props.dueAt).split('-').reverse().join('/')
);
const dueDateClasses = computed(() => {
  if (!dueDate.value) return '';

  const diffInDays = differenceInCalendarDays(dueDate.value, new Date());

  if (diffInDays <= 0) return 'bg-n-ruby-3 text-n-ruby-11';
  if (diffInDays === 1) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-teal-3 text-n-teal-11';
});
</script>

<template>
  <span
    v-show="dueDate"
    class="inline-flex flex-shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5"
    :class="dueDateClasses"
    :title="String(dueAt)"
  >
    <i class="i-lucide-calendar size-3" />
    {{ dueDateLabel }}
  </span>
</template>
