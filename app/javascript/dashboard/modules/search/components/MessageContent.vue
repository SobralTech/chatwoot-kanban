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

const { getPlainText } = useMessageFormatter();

const messageContent = computed(() => {
  // Voice-call messages carry a generic content label (e.g. "Twilio voice
  // call"), so a transcript match would otherwise be hidden behind it.
  if (
    props.message.contentType === 'voice_call' &&
    props.message.call?.transcript
  ) {
    return props.message.call.transcript;
  }

  // We perform search on either content, email subject, or transcribed text
  // (voice-note attachments)
  if (props.message.content) {
    return props.message.content;
  }

  const { email = {} } = props.message.contentAttributes || {};
  if (email.subject) {
    return email.subject;
  }

  const audioAttachment = props.message.attachments?.find(
    attachment => attachment.fileType === 'audio'
  );
  return audioAttachment?.transcribedText || '';
});

const escapeHtml = html => {
  const wrapper = document.createElement('p');
  wrapper.textContent = html;
  return wrapper.innerHTML;
};

const highlightedContent = computed(() => {
  // getPlainText decodes any markdown in the source into literal text (e.g. a
  // literal "<img ...>" in the transcript stays as visible characters rather
  // than a tag). escapeHtml then HTML-encodes that text so the highlight
  // <span> injected below is the only real markup in the final string passed
  // to v-dompurify-html.
  const plainText = getPlainText(messageContent.value || '');
  const escapedText = escapeHtml(plainText);

  const searchTerm = props.searchTerm || '';
  if (!searchTerm) {
    return escapedText;
  }

  const escapedSearchTerm = escapeHtml(searchTerm).replace(
    /[.*+?^${}()|[\]\\]/g,
    '\\$&'
  );
  return escapedText.replace(
    new RegExp(`(${escapedSearchTerm})`, 'ig'),
    '<span class="searchkey--highlight">$1</span>'
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
