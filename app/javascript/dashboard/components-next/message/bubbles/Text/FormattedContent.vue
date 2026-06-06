<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { highlightSearchTerm } from 'shared/helpers/highlightSearchTerm.js';
import { MESSAGE_VARIANTS } from '../../constants';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant, conversationSearchQuery } = useMessageContext();

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  return new MessageFormatter(props.content).formattedMessage;
});

const highlightedContent = computed(() => {
  return highlightSearchTerm(
    formattedContent.value,
    conversationSearchQuery.value,
    'conversation-search-highlight'
  );
});
</script>

<template>
  <span
    v-dompurify-html="highlightedContent"
    class="prose prose-bubble [&_.conversation-search-highlight]:bg-n-amber-5 [&_.conversation-search-highlight]:text-n-slate-12 [&_.conversation-search-highlight]:rounded-sm [&_.conversation-search-highlight]:px-0.5"
  />
</template>
