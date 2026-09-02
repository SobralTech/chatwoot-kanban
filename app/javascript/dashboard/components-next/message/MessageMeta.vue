<script setup>
import { computed } from 'vue';
import { humanTimestamp } from 'shared/helpers/timeHelper';

import MessageStatus from './MessageStatus.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageStatus } from 'dashboard/composables/useMessageStatus';
import { useMessageContext } from './provider.js';

const {
  status,
  isPrivate,
  createdAt,
  sourceId,
  messageType,
  contentAttributes,
} = useMessageContext();

const readableTime = computed(() => humanTimestamp(createdAt.value));

const { showStatusIndicator, hasFailed, statusToShow } = useMessageStatus({
  status,
  isPrivate,
  messageType,
  sourceId,
  contentAttributes,
});

// Don't show status for failed messages, we already show error message
const showStatus = computed(
  () => showStatusIndicator.value && !hasFailed.value
);
</script>

<template>
  <div class="text-xs flex items-center gap-1.5">
    <div class="inline">
      <time class="inline">{{ readableTime }}</time>
    </div>
    <Icon v-if="isPrivate" icon="i-lucide-lock-keyhole" class="size-3" />
    <MessageStatus v-if="showStatus" :status="statusToShow" />
  </div>
</template>
