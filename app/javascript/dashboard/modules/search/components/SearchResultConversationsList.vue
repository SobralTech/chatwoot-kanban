<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';

import SearchResultSection from './SearchResultSection.vue';
import SearchResultConversationItem from './SearchResultConversationItem.vue';

const props = defineProps({
  conversations: {
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

const conversationsWithSubject = computed(() => {
  return props.conversations.map(conversation => ({
    ...conversation,
    mailSubject: conversation.additionalAttributes?.mailSubject || '',
  }));
});
</script>

<template>
  <SearchResultSection
    :title="$t('SEARCH.SECTION.CONVERSATIONS')"
    :empty="!conversations.length"
    :query="query"
    :show-title="showTitle"
    :is-fetching="isFetching"
  >
    <ul v-if="conversations.length" class="space-y-3 list-none">
      <li
        v-for="conversation in conversationsWithSubject"
        :key="conversation.id"
      >
        <SearchResultConversationItem
          :id="conversation.id"
          :name="conversation.contact.name"
          :email="conversation.contact.email"
          :phone="conversation.contact.phoneNumber"
          :thumbnail="conversation.contact.thumbnail"
          :account-id="accountId"
          :inbox="conversation.inbox"
          :last-activity-at="conversation.lastActivityAt"
          :email-subject="conversation.mailSubject"
        />
      </li>
    </ul>
  </SearchResultSection>
</template>
