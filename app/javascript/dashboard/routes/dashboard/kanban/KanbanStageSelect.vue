<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
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
  // Keeps the current value readable while the regular stage list is loading
  // or no longer contains the card's stage.
  currentStage: {
    type: Object,
    default: null,
  },
  disabled: {
    type: Boolean,
    default: false,
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

// A stage without a colour still gets a dot, otherwise the row loses its
// left edge and the names stop lining up.
const dotStyle = stage => ({
  backgroundColor: stage?.color || DEFAULT_KANBAN_STAGE_COLOR,
});

const onSelect = (stage, hide) => {
  hide();
  emit('update:modelValue', Number(stage.id));
};
</script>

<template>
  <div class="min-w-0 w-full [&>span]:w-full">
    <span
      v-if="!isSelectable"
      class="flex h-10 w-full items-center gap-2 rounded-lg px-4 text-sm font-medium text-n-slate-12 outline outline-1 outline-n-strong"
      :title="stageName"
    >
      <span
        class="size-2 flex-shrink-0 rounded-full"
        :style="dotStyle(displayStage)"
        aria-hidden="true"
      />
      <span class="min-w-0 truncate">{{ stageName }}</span>
    </span>

    <Popover v-else align="start" disable-mobile-view>
      <template #default="{ isOpen }">
        <Button
          data-testid="kanban-stage-select-trigger"
          variant="outline"
          color="slate"
          justify="start"
          class="w-full"
          :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.STAGE_SELECT')"
          :title="stageName"
          :disabled="disabled"
        >
          <span
            class="size-2 flex-shrink-0 rounded-full"
            :style="dotStyle(displayStage)"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 truncate text-left">
            {{ stageName }}
          </span>
          <i
            class="size-4 flex-shrink-0 text-n-slate-10"
            :class="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          />
        </Button>
      </template>

      <template #content="{ hide }">
        <div
          class="w-64 max-w-[calc(100vw-2rem)] overflow-hidden"
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
              :style="dotStyle(stage)"
              aria-hidden="true"
            />
            <span class="min-w-0 flex-1 truncate" :title="stage.name">
              {{ stage.name }}
            </span>
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
