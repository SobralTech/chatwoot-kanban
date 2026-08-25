<script setup>
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardLabelsV5 from 'dashboard/components-next/Conversation/ConversationCard/CardLabelsV5.vue';

defineProps({
  labelTitles: {
    type: Array,
    default: () => [],
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

defineEmits(['openView']);

const { t } = useI18n();
</script>

<template>
  <div class="mt-1.5 flex min-w-0 items-center justify-between gap-2">
    <CardLabelsV5
      v-if="labelTitles.length"
      data-testid="kanban-conversation-card-labels"
      :labels="labelTitles"
      class="flex-1"
    />
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
