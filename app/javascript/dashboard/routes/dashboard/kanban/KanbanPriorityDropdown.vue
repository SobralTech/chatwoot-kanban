<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';

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
  <Popover align="start" disable-mobile-view :show-content-border="false">
    <button
      type="button"
      :data-testid="testId"
      class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="disabled"
    >
      <CardPriorityIcon
        :priority="modelValue"
        show-empty
        class="size-4 flex-shrink-0"
      />
      <span class="min-w-0 flex-1 truncate">
        {{ selectedOption.label }}
      </span>
      <i class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11" />
    </button>

    <template #content>
      <div
        class="block visible w-64 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
      >
        <ul class="grid gap-1">
          <li v-for="option in priorityOptions" :key="option.value">
            <button
              type="button"
              data-testid="kanban-priority-option"
              :data-selected="option.value === modelValue"
              class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
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
