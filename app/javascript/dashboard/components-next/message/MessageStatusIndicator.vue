<script setup>
import { computed } from 'vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMessageStatus } from 'dashboard/composables/useMessageStatus';

import MessageStatus from './MessageStatus.vue';

const props = defineProps({
  message: { type: Object, default: () => ({}) },
  // Falls back to the inbox the message itself carries.
  inboxId: { type: [Number, String], default: null },
});

// Message payloads reach this component both camelized and straight off the
// wire, so normalize before reading any field.
const message = computed(() => useCamelCase(props.message || {}));

const { showStatusIndicator, statusToShow } = useMessageStatus(
  {
    status: () => message.value.status,
    isPrivate: () => message.value.private,
    messageType: () => message.value.messageType,
    sourceId: () => message.value.sourceId,
    contentAttributes: () => message.value.contentAttributes,
  },
  () => props.inboxId || message.value.inboxId
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <MessageStatus v-if="showStatusIndicator" :status="statusToShow" />
</template>
