<script setup>
import { computed } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  message: {
    type: Object,
    default: () => ({}),
  },
  searchTerm: {
    type: String,
    default: '',
  },
});

const { highlightContent } = useMessageFormatter();

const messageContent = computed(() => {
  // We perform search on either content or email subject or transcribed text
  if (props.message.content) {
    return props.message.content;
  }

  const { content_attributes = {} } = props.message;
  const { email = {} } = content_attributes || {};
  if (email.subject) {
    return email.subject;
  }

  const audioAttachment = props.message.attachments?.find(
    attachment => attachment.file_type === 'audio'
  );
  return audioAttachment?.transcribed_text || '';
});

const escapeHtml = html => {
  const wrapper = document.createElement('p');
  wrapper.textContent = html;
  return wrapper.textContent;
};

const highlightedContent = computed(() => {
  const content = messageContent.value || '';
  const escapedText = escapeHtml(content);
  return highlightContent(
    escapedText,
    props.searchTerm,
    'searchkey--highlight'
  );
});
</script>

<template>
  <span
    v-dompurify-html="highlightedContent"
    class="message-content truncate min-w-0 text-n-slate-11 [&_.searchkey--highlight]:text-n-blue-11 [&_.searchkey--highlight]:font-semibold"
  />
</template>

<style scoped lang="scss">
.message-content :deep(p) {
  @apply inline;
  margin: 0;
}

.message-content :deep(br) {
  display: none;
}
</style>
