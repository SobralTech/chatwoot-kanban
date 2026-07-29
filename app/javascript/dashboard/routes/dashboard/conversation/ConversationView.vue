<script>
import { computed } from 'vue';
import { mapGetters } from 'vuex';
import { useWindowSize } from '@vueuse/core';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import ConversationSearchPanel from 'dashboard/components/widgets/conversation/ConversationSearchPanel.vue';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { EMBEDDED_CONVERSATION } from 'dashboard/composables/useEmbeddedConversation';
import { goBackEmbedded } from 'dashboard/helper/embeddedConversationHistory';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
    ConversationSearchPanel,
  },
  provide() {
    return {
      [EMBEDDED_CONVERSATION]: computed(() =>
        this.isEmbedded
          ? {
              sidebarOpen: this.embeddedSidebarOpen,
              setSidebarOpen: this.setEmbeddedSidebarOpen,
              goBack: this.goBackFromEmbedded,
            }
          : null
      ),
    };
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
    backRoute: {
      type: Object,
      default: null,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();

    return {
      uiSettings,
      updateUISettings,
      accountId,
      windowWidth,
    };
  },
  data() {
    return {
      showSearchModal: false,
      isConversationSearchOpen: false,
      isFetchingConversation: false,
      conversationFetchError: false,
      fetchingConversationId: null,
      isSyncingRouteWithArchivedState: false,
      embeddedSidebarOpen: true,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isEmbedded() {
      return !!this.backRoute;
    },
    isOnExpandedLayout() {
      if (this.windowWidth >= wootConstants.SMALL_SCREEN_BREAKPOINT) {
        return false;
      }
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      if (this.isConversationSearchOpen) {
        return false;
      }

      if (this.isEmbedded) {
        return this.embeddedSidebarOpen;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.conversationFetchError = false;
      this.fetchConversationIfUnavailable();
    },
    // Keeps the URL in sync when the currently open conversation's archived
    // state changes for any reason: another agent archiving/unarchiving it
    // (via the CONVERSATION_UPDATED websocket event updating currentChat
    // reactively), or the conversation already being archived when opened
    // through a stale/generic link.
    'currentChat.archived_at': function handleArchivedStateChange(archivedAt) {
      this.syncRouteWithArchivedState(archivedAt);
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
      // In embedded mode (e.g. opened from a kanban card), ChatList isn't
      // rendered, so its conversation-load event never fires to trigger
      // this. Check directly so a conversation missing from the store
      // still gets fetched.
      this.fetchConversationIfUnavailable();
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (chat) {
        return;
      }
      // Avoid firing a duplicate request for the same conversationId
      // while a previous fetch for it is still in flight.
      const isFetchingSameConversation =
        this.isFetchingConversation &&
        this.fetchingConversationId === this.conversationId;
      if (isFetchingSameConversation) {
        return;
      }
      this.loadMissingConversation();
    },
    async loadMissingConversation() {
      const { conversationId } = this;
      this.fetchingConversationId = conversationId;
      this.isFetchingConversation = true;
      this.conversationFetchError = false;
      try {
        await this.$store.dispatch('getConversation', conversationId);
        // The route may have changed while the request was in flight.
        if (this.conversationId === conversationId) {
          this.setActiveChat();
        }
      } catch (error) {
        if (this.conversationId === conversationId) {
          this.conversationFetchError = true;
        }
      } finally {
        if (this.fetchingConversationId === conversationId) {
          this.isFetchingConversation = false;
        }
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    syncRouteWithArchivedState(archivedAt) {
      if (
        this.isEmbedded ||
        !this.conversationId ||
        this.isSyncingRouteWithArchivedState
      ) {
        return;
      }
      // Ignore stale updates while currentChat hasn't caught up with the
      // conversationId the route just changed to.
      if (Number(this.currentChat.id) !== Number(this.conversationId)) {
        return;
      }

      const isArchived = !!archivedAt;
      const isOnArchivedRoute =
        this.$route.name === 'conversation_through_archived';

      if (isArchived === isOnArchivedRoute) {
        return;
      }

      // beforeRouteLeave clears the selected chat on every route-record
      // transition, including this redirect itself. That momentarily
      // resets currentChat.archived_at, which would otherwise re-trigger
      // this watcher and fire an overlapping replace() before the first
      // one resolves, endlessly cancelling each other out. Guarding
      // re-entrancy until the in-flight redirect settles keeps exactly one
      // replace() alive at a time so it can actually complete.
      this.isSyncingRouteWithArchivedState = true;
      const target = isArchived
        ? {
            name: 'conversation_through_archived',
            params: {
              accountId: this.accountId,
              conversationId: this.conversationId,
            },
          }
        : conversationListPageURL({
            accountId: this.accountId,
            conversationType: wootConstants.CONVERSATION_TYPE.ARCHIVED,
          });
      this.$router.replace(target).finally(() => {
        this.isSyncingRouteWithArchivedState = false;
      });
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        if (!selectedConversation) {
          return;
        }
        const { messageId } = this.$route.query;
        // Conversation is already active: just scroll to the requested
        // message instead of skipping navigation entirely.
        if (selectedConversation.id === this.currentChat.id) {
          this.scrollToSearchedMessage(messageId, selectedConversation.id);
          return;
        }
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            this.scrollToSearchedMessage(messageId, selectedConversation.id);
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    async scrollToSearchedMessage(messageId, conversationId) {
      if (!messageId) {
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        return;
      }
      // The message linked from search may live outside the window of
      // messages already loaded for this conversation, so fetch the
      // window around it before attempting to scroll.
      const isMessageLoaded = this.currentChat.messages?.some(
        message => Number(message.id) === Number(messageId)
      );
      if (!isMessageLoaded) {
        try {
          await this.$store.dispatch('mergeConversationMessageWindow', {
            conversationId,
            around: messageId,
            before_limit: 20,
            after_limit: 20,
          });
        } catch (error) {
          return;
        }
      }
      emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
    openConversationSearch() {
      this.isConversationSearchOpen = true;
    },
    closeConversationSearch() {
      this.isConversationSearchOpen = false;
    },
    closeConversationSearchPanel() {
      this.$refs.conversationBox?.closeConversationSearch();
    },
    onConversationSearchStateChange(searchState) {
      this.$refs.conversationBox?.onConversationSearchStateChange(searchState);
    },
    setEmbeddedSidebarOpen(value) {
      this.embeddedSidebarOpen = value;
    },
    goBackFromEmbedded() {
      goBackEmbedded(this.$router, this.backRoute);
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0">
    <ChatList
      v-if="!isEmbedded"
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />
    <ConversationBox
      v-if="showMessageView"
      ref="conversationBox"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
      :is-fetching-conversation="isFetchingConversation"
      :has-conversation-fetch-error="conversationFetchError"
      @conversation-search-open="openConversationSearch"
      @conversation-search-close="closeConversationSearch"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>
    <ConversationSearchPanel
      v-if="isConversationSearchOpen"
      @close="closeConversationSearchPanel"
      @search-state-change="onConversationSearchStateChange"
    />
    <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
    <CmdBarConversationSnooze />
  </section>
</template>
