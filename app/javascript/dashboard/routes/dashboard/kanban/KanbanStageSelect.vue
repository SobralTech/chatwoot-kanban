<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import {
  MENU_OPTION_CLASSES,
  MENU_OPTION_SELECTED_CLASSES,
  MENU_SURFACE_CLASSES,
} from './menuClasses';

const props = defineProps({
  modelValue: {
    type: [Number, String],
    default: null,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  // A card on a terminal stage never appears in the regular list, so its name
  // and color have to come from outside it for the read-only label.
  currentStage: {
    type: Object,
    default: null,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  variant: {
    type: String,
    default: 'inline',
    validator: value => ['inline', 'field'].includes(value),
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const selectedStage = computed(() =>
  props.stages.find(stage => Number(stage.id) === Number(props.modelValue))
);

// The list decides what can change: no matching entry means a plain label,
// never a dead dropdown.
const displayStage = computed(
  () => selectedStage.value || props.currentStage || {}
);
const isSelectable = computed(() => !!selectedStage.value);
const stageName = computed(
  () => displayStage.value.name || t('KANBAN.CARD.UNKNOWN_STAGE')
);

const isSelected = stage => Number(stage.id) === Number(props.modelValue);

const onSelect = (stage, hide) => {
  hide();
  emit('update:modelValue', Number(stage.id));
};
</script>

<template>
  <div :class="variant === 'field' ? 'w-full' : 'min-w-0'">
    <span
      v-if="!isSelectable"
      :class="
        variant === 'field'
          ? 'flex h-9 items-center px-3 text-sm text-n-slate-12'
          : 'inline-flex items-center gap-1.5 px-1 py-0.5 text-xs font-medium text-n-slate-12'
      "
    >
      <span
        v-if="variant === 'inline'"
        class="size-2 flex-shrink-0 rounded-full"
        :style="
          displayStage.color ? { backgroundColor: displayStage.color } : null
        "
        aria-hidden="true"
      />
      <span class="min-w-0 truncate">{{ stageName }}</span>
    </span>

    <Popover v-else align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-stage-select-trigger"
        :class="
          variant === 'field'
            ? 'flex h-9 w-full items-center justify-between gap-2 rounded-lg border-0 bg-n-surface-1 px-3 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-slate-6 focus:outline-n-blue-9 disabled:cursor-not-allowed disabled:opacity-60'
            : 'inline-flex min-w-0 items-center gap-1.5 rounded-md px-1 py-0.5 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50'
        "
        :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.STAGE_SELECT')"
        :title="t('CONVERSATION_SIDEBAR.KANBAN.STAGE_SELECT')"
        :disabled="disabled"
      >
        <span
          class="size-2 flex-shrink-0 rounded-full"
          :style="
            displayStage.color ? { backgroundColor: displayStage.color } : null
          "
          aria-hidden="true"
        />
        <span class="min-w-0 truncate">{{ stageName }}</span>
        <i
          class="i-lucide-chevron-down size-3 flex-shrink-0"
          :class="
            variant === 'field' ? 'size-4 text-n-slate-11' : 'text-n-slate-10'
          "
        />
      </button>

      <template #content="{ hide }">
        <div
          class="w-56 max-w-[calc(100vw-2rem)] overflow-hidden"
          :class="[MENU_SURFACE_CLASSES]"
        >
          <button
            v-for="stage in stages"
            :key="stage.id"
            type="button"
            data-testid="kanban-stage-select-option"
            :class="[
              MENU_OPTION_CLASSES,
              isSelected(stage) ? MENU_OPTION_SELECTED_CLASSES : '',
            ]"
            :disabled="disabled"
            @click="onSelect(stage, hide)"
          >
            <span
              class="size-2 flex-shrink-0 rounded-full"
              :style="stage.color ? { backgroundColor: stage.color } : null"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1 truncate">{{ stage.name }}</span>
            <i
              v-if="isSelected(stage)"
              class="i-lucide-check size-3.5 flex-shrink-0 text-n-brand"
            />
          </button>
        </div>
      </template>
    </Popover>
  </div>
</template>
