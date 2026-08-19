<script setup>
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  BULK_ACTION_BUTTON_CLASSES,
  BULK_ACTION_MENU_CLASSES,
  BULK_ACTION_OPTION_CLASSES,
} from './bulkActionClasses';

defineProps({
  label: {
    type: String,
    required: true,
  },
  icon: {
    type: String,
    required: true,
  },
  options: {
    type: Array,
    default: () => [],
  },
  emptyText: {
    type: String,
    default: '',
  },
  triggerTestid: {
    type: String,
    default: undefined,
  },
  optionTestid: {
    type: String,
    default: undefined,
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select']);

const choose = (value, hide) => {
  emit('select', value);
  hide?.();
};
</script>

<template>
  <Popover align="start" disable-mobile-view>
    <button
      type="button"
      :data-testid="triggerTestid"
      :class="BULK_ACTION_BUTTON_CLASSES"
      :disabled="isBusy"
    >
      <i :class="`${icon} size-4`" />
      {{ label }}
    </button>
    <template #content="{ hide }">
      <div :class="BULK_ACTION_MENU_CLASSES">
        <p
          v-if="emptyText && !options.length"
          class="px-2 py-1 text-xs text-n-slate-10"
        >
          {{ emptyText }}
        </p>
        <button
          v-for="option in options"
          :key="option.value"
          type="button"
          :data-testid="optionTestid"
          :class="BULK_ACTION_OPTION_CLASSES"
          @click="choose(option.value, hide)"
        >
          <slot name="optionIcon" :option="option" />
          <span class="truncate">{{ option.label }}</span>
        </button>
        <slot name="footer" :hide="hide" />
      </div>
    </template>
  </Popover>
</template>
