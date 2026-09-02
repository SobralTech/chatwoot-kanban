<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import KanbanDueDatePicker from '../../KanbanDueDatePicker.vue';
import KanbanPriorityDropdown from '../../KanbanPriorityDropdown.vue';
import { MENU_SURFACE_CLASSES } from '../../menuClasses';

const props = defineProps({
  accountLabels: {
    type: Array,
    default: () => [],
  },
  selectedLabelTitles: {
    type: Array,
    default: () => [],
  },
  isPending: {
    type: Function,
    default: () => false,
  },
});

const emit = defineEmits(['addLabel', 'removeLabel']);

const priority = defineModel('priority', {
  type: String,
  default: '',
});
const dueAt = defineModel('dueAt', {
  type: String,
  default: '',
});

const { t } = useI18n();

const labelsPending = computed(() => props.isPending('labels'));
const selectedLabels = computed(() =>
  props.selectedLabelTitles.map(title => {
    const accountLabel = props.accountLabels.find(
      label => label.title === title
    );
    return accountLabel || { title };
  })
);
const visibleLabels = computed(() => selectedLabels.value.slice(0, 3));
const remainingLabelCount = computed(() =>
  Math.max(selectedLabels.value.length - visibleLabels.value.length, 0)
);

const labelDropdownProps = computed(() => ({
  accountLabels: props.accountLabels,
  selectedLabels: props.selectedLabelTitles,
}));
</script>

<template>
  <!-- Secondary attributes share one borderless tier, so they stay available
  without competing with the deal state above them. -->
  <div
    data-testid="kanban-opportunity-attributes-row"
    class="-mx-1.5 flex min-w-0 flex-wrap items-center gap-x-1 gap-y-1"
  >
    <KanbanPriorityDropdown
      v-model="priority"
      compact
      test-id="kanban-opportunity-priority"
      :none-label="t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY')"
      :disabled="isPending('priority')"
    />

    <KanbanDueDatePicker
      v-model="dueAt"
      compact
      data-testid="kanban-opportunity-due-at"
      :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
      :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
      :disabled="isPending('dueAt')"
    />

    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-opportunity-labels-menu"
        class="inline-flex h-7 flex-shrink-0 items-center gap-1.5 rounded-md px-1.5 text-xs text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.LABELS')"
        :title="t('KANBAN.OPPORTUNITY_DETAILS.LABELS')"
        :disabled="labelsPending"
      >
        <i class="i-lucide-tag size-3 flex-shrink-0" />
        {{ t('KANBAN.OPPORTUNITY_DETAILS.LABELS') }}
      </button>
      <template #content>
        <div
          class="w-80 max-w-[calc(100vw-2rem)]"
          :class="[MENU_SURFACE_CLASSES]"
        >
          <LabelDropdown
            v-bind="labelDropdownProps"
            allow-creation
            @add="emit('addLabel', $event)"
            @remove="emit('removeLabel', $event)"
          />
        </div>
      </template>
    </Popover>

    <WootLabel
      v-for="label in visibleLabels"
      :key="label.id || label.title"
      data-testid="kanban-opportunity-label"
      :title="label.title"
      :color="label.color"
      :show-close="!labelsPending"
      variant="smooth"
      class="max-w-[10rem] truncate"
      @remove="emit('removeLabel', $event)"
    />

    <Popover v-if="remainingLabelCount" align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-opportunity-more-labels"
        class="flex h-7 flex-shrink-0 items-center rounded-md px-1.5 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="
          t('KANBAN.OPPORTUNITY_DETAILS.MORE_ITEMS', {
            count: remainingLabelCount,
          })
        "
        :disabled="labelsPending"
      >
        {{
          t('KANBAN.OPPORTUNITY_DETAILS.MORE_ITEMS', {
            count: remainingLabelCount,
          })
        }}
      </button>
      <template #content>
        <div
          class="w-80 max-w-[calc(100vw-2rem)]"
          :class="[MENU_SURFACE_CLASSES]"
        >
          <LabelDropdown
            v-bind="labelDropdownProps"
            allow-creation
            @add="emit('addLabel', $event)"
            @remove="emit('removeLabel', $event)"
          />
        </div>
      </template>
    </Popover>
  </div>
</template>
