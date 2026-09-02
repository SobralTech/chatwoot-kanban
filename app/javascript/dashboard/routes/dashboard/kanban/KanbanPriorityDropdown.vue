<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import { MENU_OPTION_CLASSES, MENU_SURFACE_CLASSES } from './menuClasses';

const props = defineProps({
  modelValue: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  noneLabel: {
    type: String,
    default: '',
  },
  testId: {
    type: String,
    default: 'kanban-priority-menu',
  },
  compact: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const priorityOptions = computed(() => [
  {
    value: '',
    label: props.noneLabel || t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
  },
  {
    value: CONVERSATION_PRIORITY.URGENT,
    label: t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
  },
  {
    value: CONVERSATION_PRIORITY.HIGH,
    label: t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
  },
  {
    value: CONVERSATION_PRIORITY.MEDIUM,
    label: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
  },
  {
    value: CONVERSATION_PRIORITY.LOW,
    label: t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
  },
]);

const selectedOption = computed(
  () =>
    priorityOptions.value.find(option => option.value === props.modelValue) ||
    priorityOptions.value[0]
);

const onSelect = option => {
  emit('update:modelValue', option.value);
};
</script>

<template>
  <Popover align="start" disable-mobile-view>
    <button
      type="button"
      :data-testid="testId"
      class="inline-flex min-w-0 items-center gap-1.5 rounded-md text-left outline-none hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
      :class="[
        compact
          ? 'h-7 w-auto px-1.5 py-1 text-xs text-n-slate-11 hover:text-n-slate-12 focus-visible:ring-1 focus-visible:ring-n-brand'
          : 'min-h-10 w-full border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand',
      ]"
      :disabled="disabled"
      :aria-label="selectedOption.label"
    >
      <CardPriorityIcon
        :priority="modelValue"
        show-empty
        class="flex-shrink-0"
        :class="compact ? 'size-3.5' : 'size-4'"
      />
      <!-- The label stays put when empty: an unlabelled glyph is the one
      control in the header nobody can read without clicking it. -->
      <span class="min-w-0 truncate">
        {{ selectedOption.label }}
      </span>
      <i class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-11" />
    </button>

    <template #content>
      <div class="w-64" :class="[MENU_SURFACE_CLASSES]">
        <ul class="grid gap-1">
          <li v-for="option in priorityOptions" :key="option.value">
            <button
              type="button"
              data-testid="kanban-priority-option"
              :data-selected="option.value === modelValue"
              :class="MENU_OPTION_CLASSES"
              @click="onSelect(option)"
            >
              <CardPriorityIcon
                :priority="option.value"
                show-empty
                class="size-4 flex-shrink-0"
              />
              <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
              <i
                v-if="option.value === modelValue"
                class="i-lucide-check size-4 flex-shrink-0 text-n-brand"
              />
            </button>
          </li>
        </ul>
      </div>
    </template>
  </Popover>
</template>
