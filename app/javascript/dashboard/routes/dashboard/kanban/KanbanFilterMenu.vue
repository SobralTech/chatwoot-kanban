<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

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

const updateFilter = (key, value, selected) => {
  const values = new Set(selectedValues(key));
  if (selected) values.add(value);
  else values.delete(value);

  emit('update:modelValue', {
    ...props.modelValue,
    [key]: [...values],
  });
};

const updateMatchMode = event => {
  emit('update:modelValue', {
    ...props.modelValue,
    matchMode: event.target.value,
  });
};
</script>

<template>
  <Popover align="end" disable-mobile-view>
    <button
      type="button"
      data-testid="kanban-filter-menu-trigger"
      class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
      :aria-label="t('KANBAN.FILTERS.TITLE')"
      :title="t('KANBAN.FILTERS.TITLE')"
    >
      <i class="i-lucide-list-filter size-4" />
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
            <h3
              class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ group.title }}
            </h3>
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
          <select
            class="rounded-md border border-n-weak bg-n-surface-1 px-2 py-1 text-xs text-n-slate-12 focus:border-n-brand focus:outline-none"
            :value="modelValue.matchMode"
            @change="updateMatchMode"
          >
            <option value="all">{{ t('KANBAN.FILTERS.MATCH_ALL') }}</option>
            <option value="any">{{ t('KANBAN.FILTERS.MATCH_ANY') }}</option>
          </select>
        </label>
      </div>
    </template>
  </Popover>
</template>
