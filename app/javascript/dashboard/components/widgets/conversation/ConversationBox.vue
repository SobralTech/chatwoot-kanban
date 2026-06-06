<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import MessageApi from 'dashboard/api/inbox/message';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
    NextButton,
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
      conversationSearchDebounceTimer: null,
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
    conversationSearchTotalCount() {
      return this.conversationSearchMeta.total_count || 0;
    },
    conversationSearchCurrentPosition() {
      if (
        !this.conversationSearchTotalCount ||
        this.activeConversationSearchResultIndex < 0
      ) {
        return 0;
      }

      return this.activeConversationSearchResultIndex + 1;
    },
    conversationSearchCounter() {
      return `${this.conversationSearchCurrentPosition}/${this.conversationSearchTotalCount}`;
    },
    activeConversationSearchResultId() {
      return this.conversationSearchResults[
        this.activeConversationSearchResultIndex
      ]?.id;
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
    document.addEventListener('keydown', this.onConversationSearchShortcut);
  },
  unmounted() {
    this.abortConversationSearchRequest();
    this.clearConversationSearchDebounce();
    document.removeEventListener('keydown', this.onConversationSearchShortcut);
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
      this.$nextTick(() => this.$refs.conversationSearchInput?.focus());
    },
    closeConversationSearch() {
      this.isConversationSearchOpen = false;
      this.resetConversationSearch();
    },
    resetConversationSearch() {
      this.abortConversationSearchRequest();
      this.clearConversationSearchDebounce();
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
    onConversationSearchInput(event) {
      const { value } = event.target;
      this.conversationSearchQuery = value;
      this.clearConversationSearchDebounce();
      this.conversationSearchDebounceTimer = setTimeout(() => {
        this.searchConversationMessages(value);
      }, 300);
    },
    onConversationSearchInputKeydown(event) {
      if (event.key === 'Enter' && event.shiftKey) {
        event.preventDefault();
        this.selectPreviousConversationSearchResult();
      } else if (event.key === 'Enter') {
        event.preventDefault();
        this.selectNextConversationSearchResult();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        this.closeConversationSearch();
      }
    },
    onConversationSearchShortcut(event) {
      if (!this.currentChat.id || event.key.toLowerCase() !== 'f') return;
      if (!event.ctrlKey && !event.metaKey) return;
      if (this.shouldIgnoreConversationSearchShortcut(event.target)) return;

      event.preventDefault();
      this.openConversationSearch();
    },
    shouldIgnoreConversationSearchShortcut(target) {
      const focusedElement =
        target === document ? document.activeElement : target;
      if (!focusedElement || focusedElement === document.body) return false;
      if (focusedElement === this.$refs.conversationSearchInput) return false;

      const tagName = focusedElement.tagName?.toLowerCase();
      return (
        ['input', 'textarea', 'select'].includes(tagName) ||
        focusedElement.isContentEditable
      );
    },
    clearConversationSearchDebounce() {
      if (!this.conversationSearchDebounceTimer) return;

      clearTimeout(this.conversationSearchDebounceTimer);
      this.conversationSearchDebounceTimer = null;
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
    <div
      v-if="isConversationSearchOpen"
      class="flex items-center gap-2 px-3 py-2 border-b border-n-weak bg-n-surface-1"
      data-testid="conversation-search-bar"
    >
      <div class="relative flex-1 min-w-0">
        <fluent-icon
          icon="search"
          size="16"
          class="absolute top-1/2 -translate-y-1/2 text-n-slate-10 ltr:left-2 rtl:right-2"
        />
        <input
          ref="conversationSearchInput"
          :value="conversationSearchQuery"
          type="search"
          class="block w-full h-8 py-1 text-sm rounded-lg border border-n-weak bg-n-surface-2 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:ring-1 focus:ring-n-brand ltr:pl-8 ltr:pr-3 rtl:pr-8 rtl:pl-3"
          :placeholder="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
          :aria-label="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
          data-testid="conversation-search-input"
          @input="onConversationSearchInput"
          @keydown="onConversationSearchInputKeydown"
        />
      </div>
      <span
        class="min-w-10 text-center text-xs tabular-nums text-n-slate-11"
        data-testid="conversation-search-counter"
      >
        {{ conversationSearchCounter }}
      </span>
      <span
        v-if="isSearchingConversationMessages"
        class="text-xs text-n-slate-11"
        data-testid="conversation-search-loading"
      >
        {{ $t('CONVERSATION.SEARCH.LOADING_MESSAGE') }}
      </span>
      <span
        v-else-if="conversationSearchError"
        class="text-xs text-n-ruby-11"
        data-testid="conversation-search-error"
      >
        {{ $t('CONVERSATION.SEARCH.FAILED_TO_SEARCH_MESSAGES') }}
      </span>
      <span
        v-else-if="conversationSearchQuery && !conversationSearchTotalCount"
        class="text-xs text-n-slate-11"
        data-testid="conversation-search-no-results"
      >
        {{ $t('CONVERSATION.SEARCH.NO_RESULTS') }}
      </span>
      <NextButton
        ghost
        slate
        xs
        icon="i-lucide-chevron-up"
        :disabled="!conversationSearchResults.length"
        :title="$t('CONVERSATION.SEARCH.PREVIOUS_RESULT')"
        :aria-label="$t('CONVERSATION.SEARCH.PREVIOUS_RESULT')"
        data-testid="conversation-search-previous"
        @click="selectPreviousConversationSearchResult"
      />
      <NextButton
        ghost
        slate
        xs
        icon="i-lucide-chevron-down"
        :disabled="!conversationSearchResults.length"
        :title="$t('CONVERSATION.SEARCH.NEXT_RESULT')"
        :aria-label="$t('CONVERSATION.SEARCH.NEXT_RESULT')"
        data-testid="conversation-search-next"
        @click="selectNextConversationSearchResult"
      />
      <NextButton
        ghost
        slate
        xs
        icon="i-lucide-x"
        :title="$t('CONVERSATION.SEARCH.CLOSE_SEARCH')"
        :aria-label="$t('CONVERSATION.SEARCH.CLOSE_SEARCH')"
        data-testid="conversation-search-close"
        @click="closeConversationSearch"
      />
    </div>
    <div v-show="!activeIndex" class="flex h-full min-h-0 m-0">
      <MessagesView
        v-if="currentChat.id"
        :inbox-id="inboxId"
        :is-inbox-view="isInboxView"
        :active-search-result-id="activeConversationSearchResultId"
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
