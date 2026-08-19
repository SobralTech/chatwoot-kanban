<script setup>
import { ref } from 'vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  BULK_ACTION_BUTTON_CLASSES,
  BULK_ACTION_MENU_CLASSES,
  BULK_ACTION_OPTION_CLASSES,
} from './bulkActionClasses';

const props = defineProps({
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
  // Turns the option list into a checklist that only commits once `apply` is confirmed.
  multiple: {
    type: Boolean,
    default: false,
  },
  applyLabel: {
    type: String,
    default: '',
  },
  applyIcon: {
    type: String,
    default: '',
  },
  applyTestid: {
    type: String,
    default: undefined,
  },
  menuClass: {
    type: String,
    default: '',
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select', 'apply', 'hide']);

const selected = ref([]);

const isSelected = value => selected.value.includes(value);

const choose = (value, hide) => {
  if (!props.multiple) {
    emit('select', value);
    hide?.();
    return;
  }

  selected.value = isSelected(value)
    ? selected.value.filter(item => item !== value)
    : [...selected.value, value];
};

const apply = hide => {
  emit('apply', selected.value);
  hide?.();
};

const reset = () => {
  selected.value = [];
  emit('hide');
};
</script>

<template>
  <Popover align="start" disable-mobile-view @hide="reset">
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
      <div :class="[BULK_ACTION_MENU_CLASSES, menuClass]">
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
          :role="multiple ? 'menuitemcheckbox' : undefined"
          :aria-checked="multiple ? isSelected(option.value) : undefined"
          :class="BULK_ACTION_OPTION_CLASSES"
          @click="choose(option.value, hide)"
        >
          <i
            v-if="multiple"
            class="size-4 flex-shrink-0"
            :class="
              isSelected(option.value)
                ? 'i-lucide-square-check text-n-brand'
                : 'i-lucide-square text-n-slate-9'
            "
          />
          <slot name="optionContent" :option="option">
            <slot name="optionIcon" :option="option" />
            <span class="truncate">{{ option.label }}</span>
          </slot>
        </button>
        <button
          v-if="multiple && selected.length"
          type="button"
          :data-testid="applyTestid"
          class="mt-1 flex w-full items-center justify-center gap-2 rounded-md bg-n-brand px-2 py-1.5 text-sm font-medium text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isBusy"
          @click="apply(hide)"
        >
          <i :class="`${applyIcon} size-4`" />
          {{ applyLabel }}
        </button>
        <slot name="footer" :hide="hide" />
      </div>
    </template>
  </Popover>
</template>
