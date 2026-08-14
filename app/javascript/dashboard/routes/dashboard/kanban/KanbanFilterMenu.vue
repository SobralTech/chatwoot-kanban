<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { SINGLE_VALUE_FILTER_KEYS } from 'dashboard/helper/kanbanBoardFilters';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  modelValue: {
    type: Object,
    required: true,
  },
  inboxOptions: {
    type: Array,
    default: () => [],
  },
  agentOptions: {
    type: Array,
    default: () => [],
  },
  activeCount: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');

const cardStatusOptions = computed(() => [
  { value: 'open', label: t('KANBAN.FILTERS.STATUS.OPEN') },
  { value: 'won', label: t('KANBAN.FILTERS.STATUS.WON') },
  { value: 'lost', label: t('KANBAN.FILTERS.STATUS.LOST') },
]);
const priorityOptions = computed(() => [
  { value: 'none', label: t('KANBAN.FILTERS.PRIORITY.NONE') },
  { value: 'urgent', label: t('KANBAN.FILTERS.PRIORITY.URGENT') },
  { value: 'high', label: t('KANBAN.FILTERS.PRIORITY.HIGH') },
  { value: 'medium', label: t('KANBAN.FILTERS.PRIORITY.MEDIUM') },
  { value: 'low', label: t('KANBAN.FILTERS.PRIORITY.LOW') },
]);
const dueDateOptions = computed(() => [
  { value: 'none', label: t('KANBAN.FILTERS.DUE_DATE.NONE') },
  { value: 'overdue', label: t('KANBAN.FILTERS.DUE_DATE.OVERDUE') },
  { value: 'day', label: t('KANBAN.FILTERS.DUE_DATE.DAY') },
  { value: 'week', label: t('KANBAN.FILTERS.DUE_DATE.WEEK') },
  { value: 'month', label: t('KANBAN.FILTERS.DUE_DATE.MONTH') },
]);
const labelOptions = computed(() => [
  { value: 'none', label: t('KANBAN.FILTERS.LABELS_NONE') },
  ...labels.value.map(label => ({ value: label.title, label: label.title })),
]);

const filterGroups = computed(() => [
  {
    key: 'inboxIds',
    title: t('KANBAN.FILTERS.INBOXES'),
    options: props.inboxOptions,
    truncateOption: true,
  },
  {
    key: 'assigneeIds',
    title: t('KANBAN.FILTERS.AGENTS'),
    options: props.agentOptions,
    truncateOption: true,
  },
  {
    key: 'cardStatuses',
    title: t('KANBAN.FILTERS.CARD_STATUS'),
    options: cardStatusOptions.value,
  },
  {
    key: 'priorities',
    title: t('KANBAN.FILTERS.PRIORITY.TITLE'),
    options: priorityOptions.value,
  },
  {
    key: 'dueDates',
    title: t('KANBAN.FILTERS.DUE_DATE.TITLE'),
    options: dueDateOptions.value,
  },
  {
    key: 'labels',
    title: t('KANBAN.FILTERS.LABELS'),
    options: labelOptions.value,
    truncateOption: true,
  },
]);

const selectedValues = key => props.modelValue[key] || [];
const isSelected = (key, value) => selectedValues(key).includes(value);
const isSingleValueGroup = key =>
  props.modelValue.matchMode === 'all' &&
  SINGLE_VALUE_FILTER_KEYS.includes(key);

const nextValues = (key, value, selected) => {
  if (isSingleValueGroup(key)) return selected ? [value] : [];

  const values = new Set(selectedValues(key));
  if (selected) values.add(value);
  else values.delete(value);

  return [...values];
};

const updateFilter = (key, value, selected) => {
  emit('update:modelValue', {
    ...props.modelValue,
    [key]: nextValues(key, value, selected),
  });
};

const matchModeOptions = computed(() => [
  { value: 'all', label: t('KANBAN.FILTERS.MATCH_ALL') },
  { value: 'any', label: t('KANBAN.FILTERS.MATCH_ANY') },
]);

const updateMatchMode = matchMode => {
  emit('update:modelValue', {
    ...props.modelValue,
    matchMode,
  });
};
</script>

<template>
  <Popover align="end" disable-mobile-view>
    <button
      type="button"
      data-testid="kanban-filter-menu-trigger"
      class="flex h-10 items-center justify-center gap-2 px-3 text-n-slate-11 hover:bg-n-alpha-2"
      :aria-label="t('KANBAN.FILTERS.TITLE')"
      :title="t('KANBAN.FILTERS.TITLE')"
    >
      <i class="i-lucide-list-filter size-4" />
      <span
        v-if="activeCount"
        data-testid="kanban-filter-count"
        class="flex size-5 items-center justify-center rounded-full bg-n-brand text-xs font-semibold text-white"
      >
        {{ activeCount }}
      </span>
    </button>

    <template #content="{ hide }">
      <div
        data-testid="kanban-filter-menu"
        class="flex w-80 max-w-[calc(100vw-2rem)] flex-col text-sm text-n-slate-12"
      >
        <header
          class="flex items-center justify-between border-b border-n-weak px-4 py-3"
        >
          <h2 class="font-semibold">{{ t('KANBAN.FILTERS.TITLE') }}</h2>
          <button
            type="button"
            data-testid="kanban-filter-menu-close"
            class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('KANBAN.FILTERS.CLOSE')"
            :title="t('KANBAN.FILTERS.CLOSE')"
            @click="hide"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </header>

        <div class="max-h-[min(30rem,calc(100vh-12rem))] overflow-y-auto">
          <section
            v-for="(group, index) in filterGroups"
            :key="group.key"
            class="px-4 py-3"
            :class="{
              'border-b border-n-weak': index < filterGroups.length - 1,
            }"
          >
            <div class="mb-2">
              <h3
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ group.title }}
              </h3>
              <p
                v-if="isSingleValueGroup(group.key)"
                class="mt-1 text-xs normal-case text-n-slate-10"
              >
                {{ t('KANBAN.FILTERS.SINGLE_VALUE_HINT') }}
              </p>
            </div>
            <label
              v-for="option in group.options"
              :key="option.value"
              class="flex cursor-pointer items-center gap-2 rounded px-1 py-1 hover:bg-n-alpha-2"
            >
              <Checkbox
                :model-value="isSelected(group.key, option.value)"
                @update:model-value="
                  updateFilter(group.key, option.value, $event)
                "
              />
              <span :class="{ 'min-w-0 truncate': group.truncateOption }">{{
                option.label
              }}</span>
            </label>
          </section>
        </div>

        <label
          class="flex items-center justify-between gap-3 border-t border-n-weak px-4 py-3 text-xs"
        >
          <span class="font-medium text-n-slate-11">{{
            t('KANBAN.FILTERS.MATCH_MODE')
          }}</span>
          <Select
            :model-value="modelValue.matchMode"
            :options="matchModeOptions"
            class="font-normal"
            @update:model-value="updateMatchMode"
          />
        </label>
      </div>
    </template>
  </Popover>
</template>
