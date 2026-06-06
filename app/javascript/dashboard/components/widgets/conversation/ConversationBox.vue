<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import MessageApi from 'dashboard/api/inbox/message';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
  },
  props: {
    inboxId: {
      type: [Number, String],
      default: '',
      required: false,
    },
    isInboxView: {
      type: Boolean,
      default: false,
    },
    isContactPanelOpen: {
      type: Boolean,
      default: true,
    },
    isOnExpandedLayout: {
      type: Boolean,
      default: true,
    },
  },
  data() {
    return {
      activeIndex: 0,
      isConversationSearchOpen: false,
      conversationSearchQuery: '',
      conversationSearchResults: [],
      conversationSearchMeta: {},
      conversationSearchError: null,
      isSearchingConversationMessages: false,
      activeConversationSearchResultIndex: -1,
      conversationSearchAbortController: null,
      conversationSearchRequestId: 0,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      dashboardApps: 'dashboardApps/getRecords',
    }),
    dashboardAppTabs() {
      return [
        {
          key: 'messages',
          index: 0,
          name: this.$t('CONVERSATION.DASHBOARD_APP_TAB_MESSAGES'),
        },
        ...this.dashboardApps.map((dashboardApp, index) => ({
          key: `dashboard-${dashboardApp.id}`,
          index: index + 1,
          name: dashboardApp.title,
        })),
      ];
    },
    showContactPanel() {
      return this.isContactPanelOpen && this.currentChat.id;
    },
  },
  watch: {
    'currentChat.inbox_id': {
      immediate: true,
      handler(inboxId) {
        if (inboxId) {
          this.$store.dispatch('inboxAssignableAgents/fetch', [inboxId]);
        }
      },
    },
    'currentChat.id'() {
      this.fetchLabels();
      this.activeIndex = 0;
      this.resetConversationSearch();
    },
  },
  mounted() {
    this.fetchLabels();
    this.$store.dispatch('dashboardApps/get');
  },
  unmounted() {
    this.abortConversationSearchRequest();
  },
  methods: {
    fetchLabels() {
      if (!this.currentChat.id) {
        return;
      }
      this.$store.dispatch('conversationLabels/get', this.currentChat.id);
    },
    onDashboardAppTabChange(index) {
      this.activeIndex = index;
    },
    openConversationSearch() {
      if (!this.currentChat.id) return;

      this.isConversationSearchOpen = true;
    },
    closeConversationSearch() {
      this.isConversationSearchOpen = false;
      this.resetConversationSearch();
    },
    resetConversationSearch() {
      this.abortConversationSearchRequest();
      this.conversationSearchQuery = '';
      this.conversationSearchResults = [];
      this.conversationSearchMeta = {};
      this.conversationSearchError = null;
      this.isSearchingConversationMessages = false;
      this.activeConversationSearchResultIndex = -1;
      this.conversationSearchRequestId += 1;
    },
    async searchConversationMessages(query) {
      if (!this.currentChat.id) return;

      const trimmedQuery = query.trim();
      this.conversationSearchQuery = trimmedQuery;
      this.conversationSearchError = null;

      if (!trimmedQuery) {
        this.resetConversationSearch();
        return;
      }

      this.abortConversationSearchRequest();
      const requestId = this.conversationSearchRequestId + 1;
      this.conversationSearchRequestId = requestId;
      this.conversationSearchAbortController = new AbortController();
      this.isSearchingConversationMessages = true;

      try {
        const { data } = await MessageApi.searchMessages(this.currentChat.id, {
          q: trimmedQuery,
          signal: this.conversationSearchAbortController.signal,
        });
        if (!this.isLatestConversationSearchRequest(requestId, trimmedQuery)) {
          return;
        }
        this.conversationSearchResults = data.payload || [];
        this.conversationSearchMeta = data.meta || {};
        this.activeConversationSearchResultIndex = this
          .conversationSearchResults.length
          ? 0
          : -1;
      } catch (error) {
        if (!this.isLatestConversationSearchRequest(requestId, trimmedQuery)) {
          return;
        }
        this.conversationSearchError = error;
      } finally {
        if (this.isLatestConversationSearchRequest(requestId, trimmedQuery)) {
          this.isSearchingConversationMessages = false;
        }
      }
    },
    async loadMoreConversationSearchResults() {
      if (!this.currentChat.id || !this.conversationSearchMeta.has_more) return;

      const query = this.conversationSearchQuery;
      const requestId = this.conversationSearchRequestId + 1;
      this.conversationSearchRequestId = requestId;
      this.isSearchingConversationMessages = true;
      this.conversationSearchError = null;

      try {
        const { data } = await MessageApi.searchMessages(this.currentChat.id, {
          q: query,
          limit: this.conversationSearchMeta.limit,
          before_id: this.conversationSearchMeta.next_before_id,
        });
        if (!this.isLatestConversationSearchRequest(requestId, query)) {
          return;
        }
        this.conversationSearchResults = [
          ...this.conversationSearchResults,
          ...(data.payload || []),
        ];
        this.conversationSearchMeta = data.meta || {};
      } catch (error) {
        if (!this.isLatestConversationSearchRequest(requestId, query)) {
          return;
        }
        this.conversationSearchError = error;
      } finally {
        if (this.isLatestConversationSearchRequest(requestId, query)) {
          this.isSearchingConversationMessages = false;
        }
      }
    },
    selectConversationSearchResult(index) {
      if (index < 0 || index >= this.conversationSearchResults.length) return;

      this.activeConversationSearchResultIndex = index;
    },
    selectNextConversationSearchResult() {
      if (!this.conversationSearchResults.length) return;

      const nextIndex =
        (this.activeConversationSearchResultIndex + 1) %
        this.conversationSearchResults.length;
      this.selectConversationSearchResult(nextIndex);
    },
    selectPreviousConversationSearchResult() {
      if (!this.conversationSearchResults.length) return;

      const previousIndex =
        (this.activeConversationSearchResultIndex -
          1 +
          this.conversationSearchResults.length) %
        this.conversationSearchResults.length;
      this.selectConversationSearchResult(previousIndex);
    },
    abortConversationSearchRequest() {
      if (this.conversationSearchAbortController) {
        this.conversationSearchAbortController.abort();
        this.conversationSearchAbortController = null;
      }
    },
    isLatestConversationSearchRequest(requestId, query) {
      return (
        this.conversationSearchRequestId === requestId &&
        this.conversationSearchQuery === query
      );
    },
  },
};
</script>

<template>
  <div
    class="conversation-details-wrap flex flex-col min-w-0 w-full bg-n-surface-1 relative"
    :class="{
      'border-l rtl:border-l-0 rtl:border-r border-n-weak': !isOnExpandedLayout,
    }"
  >
    <ConversationHeader
      v-if="currentChat.id"
      :chat="currentChat"
      :show-back-button="isOnExpandedLayout && !isInboxView"
      :class="{
        'border-b border-b-n-weak !pt-2': !dashboardApps.length,
      }"
    />
    <woot-tabs
      v-if="dashboardApps.length && currentChat.id"
      :index="activeIndex"
      class="h-10"
      @change="onDashboardAppTabChange"
    >
      <woot-tabs-item
        v-for="tab in dashboardAppTabs"
        :key="tab.key"
        :index="tab.index"
        :name="tab.name"
        :show-badge="false"
        is-compact
      />
    </woot-tabs>
    <div v-show="!activeIndex" class="flex h-full min-h-0 m-0">
      <MessagesView
        v-if="currentChat.id"
        :inbox-id="inboxId"
        :is-inbox-view="isInboxView"
      />
      <EmptyState
        v-if="!currentChat.id && !isInboxView"
        :is-on-expanded-layout="isOnExpandedLayout"
      />
      <slot />
    </div>
    <DashboardAppFrame
      v-for="(dashboardApp, index) in dashboardApps"
      v-show="activeIndex - 1 === index"
      :key="currentChat.id + '-' + dashboardApp.id"
      :is-visible="activeIndex - 1 === index"
      :config="dashboardApps[index].content"
      :position="index"
      :current-chat="currentChat"
    />
  </div>
</template>
