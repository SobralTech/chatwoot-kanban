<script setup>
import { useMapGetter } from 'dashboard/composables/store.js';

import SearchResultMessageItem from './SearchResultMessageItem.vue';
import SearchResultSection from './SearchResultSection.vue';
import MessageContent from './MessageContent.vue';

defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  query: {
    type: String,
    default: '',
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  showTitle: {
    type: Boolean,
    default: true,
  },
});

const accountId = useMapGetter('getCurrentAccountId');
</script>

<template>
  <SearchResultSection
    :title="$t('SEARCH.SECTION.MESSAGES')"
    :empty="!messages.length"
    :query="query"
    :show-title="showTitle"
    :is-fetching="isFetching"
  >
    <ul v-if="messages.length" class="space-y-3 list-none">
      <li v-for="message in messages" :key="message.id">
        <SearchResultMessageItem
          :id="message.conversationId"
          :account-id="accountId"
          :created-at="message.createdAt"
          :message-id="message.id"
          :contact-name="message.conversation?.contact?.name"
          :contact-thumbnail="message.conversation?.contact?.thumbnail"
          :message-type="message.messageType"
        >
          <MessageContent :message="message" :search-term="query" />
        </SearchResultMessageItem>
      </li>
    </ul>
  </SearchResultSection>
</template>
