<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  modelValue: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const CRITERIA = ['stage', 'assignee', 'priority'];

const isOpen = ref(false);
const closeMenu = () => {
  isOpen.value = false;
};

const criterionLabel = criterion =>
  t(`KANBAN.LIST.GROUP_BY.${criterion.toUpperCase()}`);

const menuItems = computed(() =>
  CRITERIA.map(criterion => ({
    action: 'groupBy',
    value: criterion,
    label: criterionLabel(criterion),
    isSelected: criterion === props.modelValue,
  }))
);

const onAction = ({ value }) => {
  closeMenu();
  if (value !== props.modelValue) emit('update:modelValue', value);
};
</script>

<template>
  <div v-on-click-outside="closeMenu" class="relative flex items-center">
    <button
      type="button"
      data-testid="kanban-list-group-by-trigger"
      class="flex h-10 min-w-0 items-center gap-2 rounded-lg px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2"
      :title="t('KANBAN.LIST.GROUP_BY.LABEL')"
      @click="isOpen = !isOpen"
    >
      <i class="i-lucide-group size-4 flex-shrink-0" />
      <span class="truncate font-medium text-n-slate-12">
        {{ criterionLabel(modelValue) }}
      </span>
      <i class="i-lucide-chevron-down size-3.5 flex-shrink-0" />
    </button>

    <DropdownMenu
      v-if="isOpen"
      data-testid="kanban-list-group-by-menu"
      :menu-items="menuItems"
      class="top-full mt-1 ltr:left-0 rtl:right-0"
      @action="onAction"
    />
  </div>
</template>
