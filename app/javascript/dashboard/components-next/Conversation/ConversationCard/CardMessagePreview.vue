<script setup>
import { computed } from 'vue';

import CardMessageContent from './CardMessageContent.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  hideAssignee: {
    type: Boolean,
    default: false,
  },
});

const assignee = computed(() => {
  const { meta: { assignee: agent = {} } = {} } = props.conversation;
  return {
    name: agent.name ?? agent.availableName,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus,
  };
});

const unreadMessagesCount = computed(() => {
  const { unreadCount } = props.conversation;
  return unreadCount;
});
</script>

<template>
  <div class="flex items-end w-full gap-2 pb-1">
    <p class="w-full mb-0 text-sm leading-7 text-n-slate-12 line-clamp-2">
      <CardMessageContent :conversation="conversation" />
    </p>
    <div class="flex items-center flex-shrink-0 gap-2 pb-2">
      <Avatar
        v-if="assignee.name && !hideAssignee"
        :name="assignee.name"
        :src="assignee.thumbnail"
        :size="20"
        :status="assignee.status"
        rounded-full
      />
      <div
        v-if="unreadMessagesCount > 0"
        class="inline-flex items-center justify-center rounded-full size-5 bg-n-brand"
      >
        <span class="text-xs font-semibold text-white">
          {{ unreadMessagesCount }}
        </span>
      </div>
    </div>
  </div>
</template>
