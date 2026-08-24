<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
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
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['addLabel', 'removeLabel']);

const { t } = useI18n();

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
  <div
    data-testid="kanban-opportunity-labels-row"
    class="flex min-w-0 flex-wrap items-center gap-2"
  >
    <Popover align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-opportunity-labels-menu"
        class="inline-flex h-7 flex-shrink-0 items-center gap-1.5 rounded-md border border-n-weak px-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.LABELS')"
        :title="t('KANBAN.OPPORTUNITY_DETAILS.LABELS')"
        :disabled="disabled"
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
      :show-close="!disabled"
      variant="smooth"
      class="max-w-[10rem] truncate"
      @remove="emit('removeLabel', $event)"
    />

    <Popover v-if="remainingLabelCount" align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-opportunity-more-labels"
        class="flex h-7 flex-shrink-0 items-center rounded-full border border-n-weak px-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="
          t('KANBAN.OPPORTUNITY_DETAILS.MORE_ITEMS', {
            count: remainingLabelCount,
          })
        "
        :disabled="disabled"
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
