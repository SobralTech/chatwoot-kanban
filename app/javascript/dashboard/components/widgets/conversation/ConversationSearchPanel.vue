<script>
import { mapGetters } from 'vuex';
import { format, fromUnixTime, isSameYear, isToday } from 'date-fns';
import MessageApi from 'dashboard/api/inbox/message';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { highlightSearchTerm } from 'shared/helpers/highlightSearchTerm.js';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export default {
  components: {
    NextButton,
    Spinner,
  },
  emits: ['close', 'searchStateChange'],
  data() {
    return {
      conversationSearchQuery: '',
      conversationSearchResults: [],
      conversationSearchMeta: {},
      conversationSearchError: null,
      isSearchingConversationMessages: false,
      activeConversationSearchResultIndex: -1,
      conversationSearchAbortController: null,
      conversationSearchRequestId: 0,
      conversationSearchDebounceTimer: null,
      isLoadingConversationSearchResult: false,
      conversationSearchNavigationError: null,
      conversationSearchNavigationController: null,
      conversationSearchNavigationRequestId: 0,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
    }),
    activeConversationSearchResultId() {
      return this.conversationSearchResults[
        this.activeConversationSearchResultIndex
      ]?.id;
    },
    hasMoreConversationSearchResults() {
      return !!this.conversationSearchMeta.has_more;
    },
    shouldShowEmptyState() {
      return (
        this.conversationSearchQuery &&
        !this.isSearchingConversationMessages &&
        !this.conversationSearchResults.length &&
        !this.conversationSearchError
      );
    },
  },
  watch: {
    'currentChat.id'() {
      this.resetConversationSearch();
    },
    conversationSearchQuery() {
      this.emitSearchStateChange();
    },
    activeConversationSearchResultId() {
      this.emitSearchStateChange();
    },
  },
  mounted() {
    this.focusInput();
  },
  unmounted() {
    this.resetConversationSearch();
  },
  methods: {
    focusInput() {
      this.$nextTick(() => this.$refs.conversationSearchInput?.focus());
    },
    emitSearchStateChange() {
      this.$emit('searchStateChange', {
        query: this.conversationSearchQuery,
        activeResultId: this.activeConversationSearchResultId || null,
      });
    },
    closePanel() {
      this.resetConversationSearch();
      this.$emit('close');
    },
    resetConversationSearch() {
      this.abortConversationSearchRequest();
      this.abortConversationSearchNavigationRequest();
      this.clearConversationSearchDebounce();
      this.conversationSearchQuery = '';
      this.conversationSearchResults = [];
      this.conversationSearchMeta = {};
      this.conversationSearchError = null;
      this.conversationSearchNavigationError = null;
      this.isSearchingConversationMessages = false;
      this.isLoadingConversationSearchResult = false;
      this.activeConversationSearchResultIndex = -1;
      this.conversationSearchRequestId += 1;
      this.conversationSearchNavigationRequestId += 1;
      this.emitSearchStateChange();
    },
    async searchConversationMessages(query) {
      if (!this.currentChat.id) return;

      const trimmedQuery = query.trim();
      this.conversationSearchQuery = trimmedQuery;
      this.conversationSearchError = null;
      this.conversationSearchNavigationError = null;
      this.abortConversationSearchNavigationRequest();

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
        this.activeConversationSearchResultIndex = -1;
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
    clearConversationSearchInput() {
      this.resetConversationSearch();
      this.focusInput();
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
        this.closePanel();
      }
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
    async selectConversationSearchResult(index) {
      if (index < 0 || index >= this.conversationSearchResults.length) return;

      this.activeConversationSearchResultIndex = index;
      this.conversationSearchNavigationError = null;

      const result = this.conversationSearchResults[index];
      if (this.isConversationSearchResultLoaded(result.id)) {
        this.abortConversationSearchNavigationRequest();
        this.isLoadingConversationSearchResult = false;
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId: result.id });
        return;
      }

      await this.loadConversationSearchResultWindow(result.id);
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
    abortConversationSearchNavigationRequest() {
      if (this.conversationSearchNavigationController) {
        this.conversationSearchNavigationController.abort();
        this.conversationSearchNavigationController = null;
      }
    },
    isLatestConversationSearchRequest(requestId, query) {
      return (
        this.conversationSearchRequestId === requestId &&
        this.conversationSearchQuery === query
      );
    },
    isConversationSearchResultLoaded(messageId) {
      return this.currentChat.messages?.some(
        message => Number(message.id) === Number(messageId)
      );
    },
    isLatestConversationSearchNavigationRequest({
      requestId,
      conversationId,
      messageId,
    }) {
      return (
        this.conversationSearchNavigationRequestId === requestId &&
        Number(this.currentChat.id) === Number(conversationId) &&
        Number(this.activeConversationSearchResultId) === Number(messageId)
      );
    },
    isAbortError(error) {
      return error?.name === 'AbortError' || error?.code === 'ERR_CANCELED';
    },
    async loadConversationSearchResultWindow(messageId) {
      this.abortConversationSearchNavigationRequest();

      const conversationId = this.currentChat.id;
      const requestId = this.conversationSearchNavigationRequestId + 1;
      this.conversationSearchNavigationRequestId = requestId;
      this.conversationSearchNavigationController = new AbortController();
      this.isLoadingConversationSearchResult = true;

      try {
        await this.$store.dispatch('mergeConversationMessageWindow', {
          conversationId,
          around: messageId,
          before_limit: 20,
          after_limit: 20,
          signal: this.conversationSearchNavigationController.signal,
        });

        if (
          !this.isLatestConversationSearchNavigationRequest({
            requestId,
            conversationId,
            messageId,
          })
        ) {
          return;
        }

        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
      } catch (error) {
        if (
          this.isAbortError(error) ||
          !this.isLatestConversationSearchNavigationRequest({
            requestId,
            conversationId,
            messageId,
          })
        ) {
          return;
        }

        this.conversationSearchNavigationError =
          error?.response?.status === 404
            ? this.$t('CONVERSATION.SEARCH.MESSAGE_UNAVAILABLE')
            : this.$t('CONVERSATION.SEARCH.FAILED_TO_LOAD_MESSAGE');
      } finally {
        if (
          this.isLatestConversationSearchNavigationRequest({
            requestId,
            conversationId,
            messageId,
          })
        ) {
          this.isLoadingConversationSearchResult = false;
        }
      }
    },
    getMessageContent(message = {}) {
      if (message.content) return message.content;

      const { content_attributes: contentAttributes = {} } = message;
      const { email = {} } = contentAttributes || {};
      if (email.subject) return email.subject;

      const audioAttachment = message.attachments?.find(
        attachment => attachment.file_type === 'audio'
      );
      return audioAttachment?.transcribed_text || '';
    },
    getMessageSender(message = {}) {
      if (message.sender?.name) return message.sender.name;
      if (message.sender_name) return message.sender_name;
      if (message.sender_type === 'User') {
        return this.$t('CONVERSATION.SEARCH.AGENT');
      }
      return this.$t('CONVERSATION.SEARCH.CONTACT');
    },
    getMessageTime(message = {}) {
      if (!message.created_at) return '';

      const date = fromUnixTime(Number(message.created_at));
      if (isToday(date)) return format(date, 'HH:mm');
      if (isSameYear(date, new Date())) return format(date, 'MMM d');
      return format(date, 'MMM d, yyyy');
    },
    hasAttachments(message = {}) {
      return !!message.attachments?.length;
    },
    getCompactMessageContent(message = {}) {
      return this.getMessageContent(message).replace(/\s+/g, ' ').trim();
    },
    escapeHtml(content = '') {
      const wrapper = document.createElement('p');
      wrapper.textContent = content;
      return wrapper.innerHTML;
    },
    getHighlightedContent(message = {}) {
      return highlightSearchTerm(
        this.escapeHtml(this.getCompactMessageContent(message)),
        this.conversationSearchQuery,
        'conversation-search-panel-highlight'
      );
    },
  },
};
</script>

<template>
  <aside
    class="flex flex-col h-full w-[320px] min-w-[320px] 2xl:w-[360px] 2xl:min-w-[360px] bg-n-surface-2 border-l rtl:border-l-0 rtl:border-r border-n-weak"
    data-testid="conversation-search-panel"
  >
    <header
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
    >
      <h2 class="text-base font-medium text-n-slate-12">
        {{ $t('CONVERSATION.SEARCH.PANEL_TITLE') }}
      </h2>
      <NextButton
        ghost
        slate
        xs
        icon="i-lucide-x"
        :title="$t('CONVERSATION.SEARCH.CLOSE_SEARCH')"
        :aria-label="$t('CONVERSATION.SEARCH.CLOSE_SEARCH')"
        data-testid="conversation-search-close"
        @click="closePanel"
      />
    </header>

    <div class="px-3 py-3 border-b border-n-weak">
      <div class="relative">
        <fluent-icon
          icon="search"
          size="16"
          class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-n-slate-10 rtl:left-auto rtl:right-3"
        />
        <input
          ref="conversationSearchInput"
          :value="conversationSearchQuery"
          type="search"
          class="reset-base block w-full h-9 mb-0 rounded-lg border border-n-weak bg-n-surface-1 py-1 pl-12 pr-12 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:outline-none focus:ring-1 focus:ring-n-brand rtl:pl-12 rtl:pr-10"
          :placeholder="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
          :aria-label="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
          data-testid="conversation-search-input"
          @input="onConversationSearchInput"
          @keydown="onConversationSearchInputKeydown"
        />
        <button
          v-if="conversationSearchQuery"
          type="button"
          class="absolute right-1 top-1/2 flex size-7 -translate-y-1/2 items-center justify-center rounded-md text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand rtl:left-1 rtl:right-auto"
          :aria-label="$t('CONVERSATION.SEARCH.CLEAR_SEARCH')"
          :title="$t('CONVERSATION.SEARCH.CLEAR_SEARCH')"
          data-testid="conversation-search-clear"
          @click="clearConversationSearchInput"
        >
          <i class="i-lucide-x size-4" />
        </button>
      </div>
      <p
        v-if="conversationSearchNavigationError"
        class="mt-2 text-xs text-n-ruby-11"
        data-testid="conversation-search-error"
      >
        {{ conversationSearchNavigationError }}
      </p>
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <div
        v-if="
          isSearchingConversationMessages && !conversationSearchResults.length
        "
        class="flex items-center justify-center h-24"
        data-testid="conversation-search-loading"
      >
        <Spinner class="text-n-brand" />
      </div>
      <div
        v-else-if="conversationSearchError"
        class="px-4 py-6 text-sm text-center text-n-ruby-11"
        data-testid="conversation-search-error"
      >
        {{ $t('CONVERSATION.SEARCH.FAILED_TO_SEARCH_MESSAGES') }}
      </div>
      <div
        v-else-if="shouldShowEmptyState"
        class="px-4 py-6 text-sm text-center text-n-slate-11"
        data-testid="conversation-search-no-results"
      >
        {{ $t('CONVERSATION.SEARCH.NO_RESULTS') }}
      </div>
      <ul
        v-if="conversationSearchResults.length"
        class="divide-y divide-n-weak"
        data-testid="conversation-search-results"
      >
        <li
          v-for="(result, index) in conversationSearchResults"
          :key="result.id"
        >
          <button
            type="button"
            class="block w-full px-4 py-3 text-left bg-transparent hover:bg-n-alpha-1 focus:outline-none focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-n-brand"
            :class="{
              'bg-n-alpha-2': index === activeConversationSearchResultIndex,
            }"
            data-testid="conversation-search-result"
            @click="selectConversationSearchResult(index)"
          >
            <div class="flex items-center justify-between gap-2">
              <span
                class="min-w-0 text-sm font-medium truncate text-n-slate-12"
              >
                {{ getMessageSender(result) }}
              </span>
              <span class="text-xs shrink-0 text-n-slate-10">
                {{ getMessageTime(result) }}
              </span>
            </div>
            <div class="flex items-start gap-1 mt-1 text-sm text-n-slate-11">
              <fluent-icon
                v-if="hasAttachments(result)"
                icon="attach"
                size="14"
                class="mt-0.5 shrink-0 text-n-slate-10"
                :title="$t('CONVERSATION.SEARCH.HAS_ATTACHMENT')"
              />
              <span
                v-dompurify-html="getHighlightedContent(result)"
                class="line-clamp-2 break-words [&_.conversation-search-panel-highlight]:bg-n-amber-5 [&_.conversation-search-panel-highlight]:text-n-slate-12 [&_.conversation-search-panel-highlight]:rounded-sm [&_.conversation-search-panel-highlight]:px-0.5"
              />
            </div>
          </button>
        </li>
      </ul>
    </div>

    <footer
      v-if="hasMoreConversationSearchResults"
      class="p-3 border-t border-n-weak"
    >
      <NextButton
        slate
        faded
        sm
        class="w-full"
        :is-loading="isSearchingConversationMessages"
        :label="$t('CONVERSATION.SEARCH.LOAD_MORE')"
        data-testid="conversation-search-load-more"
        @click="loadMoreConversationSearchResults"
      />
    </footer>
  </aside>
</template>
