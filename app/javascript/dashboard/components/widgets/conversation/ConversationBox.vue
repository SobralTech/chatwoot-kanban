<script>
import { mapGetters } from 'vuex';
import ConversationHeader from './ConversationHeader.vue';
import DashboardAppFrame from '../DashboardApp/Frame.vue';
import EmptyState from './EmptyState/EmptyState.vue';
import MessagesView from './MessagesView.vue';
import EmbeddedBackButton from './EmbeddedBackButton.vue';
import {
  useContactSidebar,
  useEmbeddedConversation,
} from 'dashboard/composables/useEmbeddedConversation';

export default {
  components: {
    ConversationHeader,
    DashboardAppFrame,
    EmptyState,
    MessagesView,
    EmbeddedBackButton,
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
    isOnExpandedLayout: {
      type: Boolean,
      default: true,
    },
    isFetchingConversation: {
      type: Boolean,
      default: false,
    },
    hasConversationFetchError: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['conversationSearchOpen', 'conversationSearchClose'],
  setup() {
    const { closeSidePanels } = useContactSidebar();

    return {
      embeddedConversation: useEmbeddedConversation(),
      closeSidePanels,
    };
  },
  data() {
    return {
      activeIndex: 0,
      isConversationSearchOpen: false,
      conversationSearchQuery: '',
      activeConversationSearchResultId: null,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      dashboardApps: 'dashboardApps/getRecords',
      uiSettings: 'getUISettings',
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
      this.closeConversationSearch();
    },
    'uiSettings.is_contact_sidebar_open'(isOpen) {
      if (isOpen) {
        this.closeConversationSearch();
      }
    },
  },
  mounted() {
    this.fetchLabels();
    this.$store.dispatch('dashboardApps/get');
    document.addEventListener('keydown', this.onConversationSearchShortcut);
  },
  unmounted() {
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
      this.$emit('conversationSearchOpen');
      this.closeSidePanels();
    },
    toggleConversationSearch() {
      if (this.isConversationSearchOpen) {
        this.closeConversationSearch();
      } else {
        this.openConversationSearch();
      }
    },
    closeConversationSearch() {
      const wasOpen = this.isConversationSearchOpen;
      this.isConversationSearchOpen = false;
      this.conversationSearchQuery = '';
      this.activeConversationSearchResultId = null;
      if (wasOpen) {
        this.$emit('conversationSearchClose');
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
      if (
        focusedElement ===
        this.$refs.conversationSearchPanel?.$refs.conversationSearchInput
      ) {
        return false;
      }

      const tagName = focusedElement.tagName?.toLowerCase();
      return (
        ['input', 'textarea', 'select'].includes(tagName) ||
        focusedElement.isContentEditable
      );
    },
    onContactDetailsToggle(isOpen) {
      if (isOpen) {
        this.closeConversationSearch();
      }
    },
    onConversationSearchStateChange({ query, activeResultId }) {
      this.conversationSearchQuery = query;
      this.activeConversationSearchResultId = activeResultId;
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
      @open-conversation-search="toggleConversationSearch"
      @toggle-contact-details="onContactDetailsToggle"
    />
    <div
      v-else-if="embeddedConversation"
      class="flex min-h-12 items-center border-b border-b-n-weak px-3 py-2"
    >
      <EmbeddedBackButton />
    </div>
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
      v-show="!activeIndex"
      class="flex h-full min-h-0 m-0"
      data-testid="conversation-main-region"
    >
      <MessagesView
        v-if="currentChat.id"
        :inbox-id="inboxId"
        :is-inbox-view="isInboxView"
        :conversation-search-query="conversationSearchQuery"
        :active-conversation-search-result-id="activeConversationSearchResultId"
      />
      <EmptyState
        v-if="!currentChat.id && !isInboxView"
        :is-on-expanded-layout="isOnExpandedLayout"
        :is-fetching-conversation="isFetchingConversation"
        :has-conversation-fetch-error="hasConversationFetchError"
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
