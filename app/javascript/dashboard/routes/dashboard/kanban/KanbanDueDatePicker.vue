<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  addDays,
  addMonths,
  endOfMonth,
  endOfWeek,
  getYear,
  isSameDay,
  isSameMonth,
  isToday,
  setMonth,
  setYear,
  startOfMonth,
  startOfWeek,
} from 'date-fns';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { MENU_SURFACE_CLASSES } from './menuClasses';

const props = defineProps({
  label: {
    type: String,
    default: '',
  },
  placeholder: {
    type: String,
    required: true,
  },
  clearLabel: {
    type: String,
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['change']);

const modelValue = defineModel({
  type: String,
  default: '',
});

const { t } = useI18n();

const monthOptions = computed(() =>
  Array.from({ length: 12 }, (_, index) => ({
    value: index,
    label: t(`KANBAN.OPPORTUNITY_DETAILS.MONTHS.${index}`),
  }))
);
const weekdayLabels = computed(() =>
  Array.from({ length: 7 }, (_, index) =>
    t(`KANBAN.OPPORTUNITY_DETAILS.WEEKDAYS_SHORT.${index}`)
  )
);

const parseDateValue = value => {
  if (!value) return null;

  const dateOnlyMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (dateOnlyMatch) {
    const [, year, month, day] = dateOnlyMatch;
    return new Date(Number(year), Number(month) - 1, Number(day));
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;

  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
};

const toDateValue = date => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  return `${year}-${month}-${day}`;
};

const formatDate = date => {
  if (!date) return '';

  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');

  return `${day}/${month}/${date.getFullYear()}`;
};

const selectedDate = computed(() => parseDateValue(modelValue.value));
const currentMonth = ref(startOfMonth(selectedDate.value || new Date()));
const yearOptions = computed(() => {
  const selectedYear = getYear(currentMonth.value);
  const startYear = selectedYear - 8;

  return Array.from({ length: 17 }, (_, index) => startYear + index);
});
const yearSelectOptions = computed(() =>
  yearOptions.value.map(year => ({ value: year, label: String(year) }))
);
const calendarDays = computed(() => {
  const start = startOfWeek(startOfMonth(currentMonth.value), {
    weekStartsOn: 0,
  });
  const end = endOfWeek(endOfMonth(currentMonth.value), { weekStartsOn: 0 });
  const days = [];

  for (let day = start; day <= end; day = addDays(day, 1)) {
    days.push(day);
  }

  return days;
});
const buttonLabel = computed(() =>
  selectedDate.value ? formatDate(selectedDate.value) : props.placeholder
);

watch(
  selectedDate,
  value => {
    if (value) currentMonth.value = startOfMonth(value);
  },
  { immediate: true }
);

// Emit the new value directly: defineModel only writes back on the next parent
// render, so reading modelValue here would still give the previous value.
const selectDate = (date, hide) => {
  const value = toDateValue(date);
  modelValue.value = value;
  emit('change', value);
  hide();
};

const clearDate = () => {
  modelValue.value = '';
  emit('change', '');
};

const setCurrentMonth = value => {
  currentMonth.value = setMonth(currentMonth.value, Number(value));
};

const setCurrentYear = value => {
  currentMonth.value = setYear(currentMonth.value, Number(value));
};

const dayClasses = day => ({
  'text-n-slate-10': !isSameMonth(day, currentMonth.value),
  'text-n-slate-12 hover:bg-n-blue-6 dark:hover:bg-n-blue-7': isSameMonth(
    day,
    currentMonth.value
  ),
  'bg-n-brand !text-white hover:bg-n-brand':
    selectedDate.value && isSameDay(day, selectedDate.value),
  'outline outline-1 outline-n-blue-8 -outline-offset-1 !text-n-blue-11':
    isToday(day) &&
    (!selectedDate.value || !isSameDay(day, selectedDate.value)),
});
</script>

<template>
  <div :class="compact ? 'flex min-w-0' : 'grid gap-1.5 [&>span]:w-full'">
    <span v-if="label" class="text-sm font-medium text-n-slate-12">
      {{ label }}
    </span>

    <Popover align="start" disable-mobile-view>
      <div :class="compact ? 'flex min-w-0 gap-0.5' : 'flex w-full gap-2'">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-md text-left outline-none hover:bg-n-alpha-2"
          :class="[
            compact
              ? 'h-7 w-auto min-w-0 px-1.5 py-1 text-xs text-n-slate-11 hover:text-n-slate-12 focus-visible:ring-1 focus-visible:ring-n-brand'
              : 'min-h-10 flex-1 border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand',
          ]"
          :aria-label="props.label || props.placeholder"
          :disabled="disabled"
        >
          <i class="i-lucide-calendar size-3 flex-shrink-0 text-n-slate-11" />
          <span class="min-w-0 truncate">{{ buttonLabel }}</span>
          <i
            class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-11"
          />
        </button>
        <button
          v-if="selectedDate"
          type="button"
          :class="
            compact
              ? 'size-7'
              : 'min-h-10 w-10 border border-n-weak bg-n-surface-1'
          "
          class="flex flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="clearLabel"
          :disabled="disabled"
          @click.stop="clearDate"
        >
          <i class="i-lucide-x size-4" />
        </button>
      </div>

      <template #content="{ hide }">
        <div class="w-80 select-none" :class="[MENU_SURFACE_CLASSES]">
          <div class="mb-3 flex items-center gap-2">
            <button
              type="button"
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :disabled="disabled"
              @click="currentMonth = addMonths(currentMonth, -1)"
            >
              <i class="i-lucide-chevron-left size-4" />
            </button>

            <Select
              :model-value="currentMonth.getMonth()"
              :options="monthOptions"
              :disabled="disabled"
              full-width
              class="flex-1"
              @update:model-value="setCurrentMonth"
            />

            <div class="w-28 flex-shrink-0">
              <Select
                :model-value="currentMonth.getFullYear()"
                :options="yearSelectOptions"
                :disabled="disabled"
                full-width
                @update:model-value="setCurrentYear"
              />
            </div>

            <button
              type="button"
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :disabled="disabled"
              @click="currentMonth = addMonths(currentMonth, 1)"
            >
              <i class="i-lucide-chevron-right size-4" />
            </button>
          </div>

          <div class="grid grid-cols-7 gap-1 text-center">
            <span
              v-for="weekday in weekdayLabels"
              :key="weekday"
              class="py-1 text-xs font-medium text-n-slate-11"
            >
              {{ weekday }}
            </span>
            <button
              v-for="day in calendarDays"
              :key="day.getTime()"
              type="button"
              class="flex h-9 items-center justify-center rounded-lg text-sm font-medium"
              :class="dayClasses(day)"
              :disabled="disabled"
              @click="selectDate(day, hide)"
            >
              {{ day.getDate() }}
            </button>
          </div>
        </div>
      </template>
    </Popover>
  </div>
</template>
