<script setup>
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import WootLabel from 'dashboard/components/ui/Label.vue';

defineProps({
  visibleLabels: {
    type: Array,
    default: () => [],
  },
  labelTitles: {
    type: Array,
    default: () => [],
  },
  extraLabelCount: {
    type: Number,
    default: 0,
  },
  assignees: {
    type: Array,
    default: () => [],
  },
  extraAssigneeCount: {
    type: Number,
    default: 0,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

// Read-only rows: clicking either group lands on the matching menu view.
defineEmits(['openView']);

const { t } = useI18n();
</script>

<template>
  <div class="mt-1.5 flex min-w-0 items-center justify-between gap-2">
    <button
      v-if="visibleLabels.length"
      type="button"
      data-testid="kanban-conversation-card-labels"
      class="flex min-w-0 cursor-pointer items-center gap-1 p-0"
      :aria-label="t('CONVERSATION_SIDEBAR.KANBAN.LABELS')"
      :disabled="disabled"
      @click.stop="$emit('openView', 'labels')"
    >
      <WootLabel
        v-for="label in visibleLabels"
        :key="label.id || label.title"
        data-testid="kanban-conversation-card-label"
        :title="label.title"
        :color="label.color"
        variant="smooth"
        small
        class="max-w-[7rem]"
      />
      <span
        v-if="extraLabelCount"
        class="text-xs text-n-slate-10"
        :title="labelTitles.join(', ')"
      >
        {{ t('KANBAN.OVERVIEW.EXTRA_COUNT', { count: extraLabelCount }) }}
      </span>
    </button>
    <button
      v-if="assignees.length"
      type="button"
      data-testid="kanban-conversation-card-assignees"
      class="-space-x-1 ml-auto flex flex-shrink-0 cursor-pointer items-center p-0"
      :aria-label="t('KANBAN.CARD.ASSIGN_TO')"
      :disabled="disabled"
      @click.stop="$emit('openView', 'assign')"
    >
      <Avatar
        v-for="assignee in assignees.slice(0, 2)"
        :key="assignee.id"
        :name="assignee.name"
        :src="assignee.avatarUrl"
        :size="16"
        rounded-full
      />
      <span v-if="extraAssigneeCount" class="pl-1 text-xs text-n-slate-10">
        {{ t('KANBAN.OVERVIEW.EXTRA_COUNT', { count: extraAssigneeCount }) }}
      </span>
    </button>
  </div>
</template>
