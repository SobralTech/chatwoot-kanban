<script>
import {
  ref,
  computed,
  provide,
  inject,
  nextTick,
  useTemplateRef,
  getCurrentInstance,
} from 'vue';
import {
  useElementSize,
  useEventListener,
  useResizeObserver,
  useSessionStorage,
} from '@vueuse/core';
// composable
import { useTrack } from 'dashboard/composables';
import { useCampaignHistory } from 'dashboard/composables/useCampaignHistory';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { CONTACT_CONVERSATION_NAVIGATION } from 'dashboard/composables/useContactConversationNavigation';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import ContactConversationLink from './ContactConversationLink.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CollapsedReplyBar from './CollapsedReplyBar.vue';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';
import ReferralBubble from 'dashboard/components-next/Conversation/ReferralBubble.vue';

// stores and apis
import { mapGetters } from 'vuex';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { getTypingUsersText } from '../../../helper/commons';
import { captureTimelineAnchor } from './helpers/campaignScrollAnchor';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { CMD_AI_ASSIST } from 'dashboard/helper/commandbar/events';
import { REPLY_POLICY } from 'shared/constants/links';
import { META_RESTRICTION_STATUS_URL } from 'dashboard/constants/globals';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import { CONVERSATION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

// distance from the bottom of the list that still counts as "at the bottom",
// same order as the threshold used to paginate older messages
const NEAR_BOTTOM_THRESHOLD = 100;
const MESSAGE_GAP_SCROLL_THRESHOLD = 100;
const FOLD_MOTION =
  'duration-300 ease-[cubic-bezier(0.32,0.72,0,1)] motion-reduce:duration-0';
const FOLD_ACTIVE_CLASS = `transition-[grid-template-rows,opacity] [&>div]:overflow-hidden ${FOLD_MOTION}`;
const FOLD_HIDDEN_CLASS = '[--fold-rows:0fr] opacity-0';
const FOLD_TRANSITION = {
  enterActiveClass: FOLD_ACTIVE_CLASS,
  leaveActiveClass: FOLD_ACTIVE_CLASS,
  enterFromClass: FOLD_HIDDEN_CLASS,
  leaveToClass: FOLD_HIDDEN_CLASS,
};

export default {
  components: {
    MessageList,
    ReplyBox,
    Banner,
    ContactConversationLink,
    Spinner,
    NextButton,
    CollapsedReplyBar,
    ResizableEditorWrapper,
    ReferralBubble,
  },
  mixins: [inboxMixin],
  props: {
    conversationSearchQuery: {
      type: String,
      default: '',
    },
    activeConversationSearchResultId: {
      type: Number,
      default: null,
    },
  },
  setup() {
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const replyBoxRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);

    const {
      olderConversation,
      newerConversation,
      isReadingHistory,
      latestConversation,
      leaveReadingMode,
      openConversation,
      buildConversationPath,
    } = inject(CONTACT_CONVERSATION_NAVIGATION);

    provide('contextMenuElementTarget', conversationPanelRef);

    const isReplyBoxCollapsed = useSessionStorage(
      SESSION_STORAGE_KEYS.REPLY_BOX_COLLAPSED,
      false
    );
    const isReplyFolded = computed(
      () => isReadingHistory.value || isReplyBoxCollapsed.value
    );
    const canSendPublicReply = computed(
      () => replyBoxRef.value?.canSendPublicReply ?? true
    );

    const collapseReplyBox = () => {
      isReplyBoxCollapsed.value = true;
      useTrack(CONVERSATION_EVENTS.COLLAPSED_REPLY_BOX);
    };
    const showReplyBox = () => {
      isReplyBoxCollapsed.value = false;
      leaveReadingMode();
    };
    // The editor focuses itself on these shortcuts, but only once it is shown.
    const revealReplyBox = mode => {
      if (!isReplyFolded.value) return;
      showReplyBox();
      useTrack(CONVERSATION_EVENTS.EXPANDED_REPLY_BOX, { mode });
      nextTick(() => {
        const replyBox = replyBoxRef.value;
        // Switching modes drops attachments, so only switch when it changes
        if (mode && replyBox.replyType !== mode) replyBox.setReplyMode(mode);
        replyBox.messageEditor?.focusEditorInputField();
      });
    };
    const revealOnShortcut = {
      action: () => revealReplyBox(),
      allowOnFocusedInput: false,
    };
    useKeyboardEvents({
      'Alt+KeyP': revealOnShortcut,
      'Alt+KeyL': revealOnShortcut,
    });
    // A shrinking list keeps its scrollTop, so a list resting at its end would
    // slide under the composer. A growing one is clamped by the browser.
    const { proxy } = getCurrentInstance();
    let listHeight = 0;
    useResizeObserver(conversationPanelRef, ([{ target }]) => {
      const shrink = listHeight - target.clientHeight;
      listHeight = target.clientHeight;
      const { scrollTop, scrollHeight, clientHeight } = target;
      const wasAtEnd = scrollHeight - scrollTop - clientHeight <= shrink + 1;
      if (shrink <= 0 || !wasAtEnd) return;
      proxy.isProgrammaticScroll = true;
      target.scrollTop = scrollHeight - clientHeight;
    });
    // ReplyBox attaches pasted files from anywhere on the page, folded or not.
    useEventListener(document, 'paste', e => {
      if (e.clipboardData?.files.length) revealReplyBox();
    });

    return {
      ...useCampaignHistory(),
      olderConversation,
      newerConversation,
      openConversation,
      buildConversationPath,
      isReadingHistory,
      isReplyFolded,
      canSendPublicReply,
      foldMotion: FOLD_MOTION,
      foldTransition: FOLD_TRANSITION,
      latestConversation,
      collapseReplyBox,
      showReplyBox,
      revealReplyBox,
      conversationPanelRef,
      resizableEditorWrapperRef,
      replyBoxRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      heightBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      isProgrammaticScroll: false,
      programmaticScrollTimer: null,
      newMessageCount: 0,
      isNearBottom: true,
      isMessageGapLoading: false,
      messageGapLoadRequestId: 0,
      lastScrollTop: 0,
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      listLoadingStatus: 'getAllMessagesLoaded',
      isMetaMessageSendingDisabled: 'globalConfig/isMetaMessageSendingDisabled',
    }),
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        return filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    referralData() {
      return this.currentChat?.additional_attributes?.referral || null;
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious) ||
        !this.isCampaignHistoryReady
      );
    },
    timelineMessages() {
      return this.isCampaignHistoryReady ? this.getMessages : [];
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },
    isInstagramRestrictionBannerVisible() {
      return this.isMetaMessageSendingDisabled && this.isAnInstagramChannel;
    },
    instagramRestrictionStatusUrl() {
      return META_RESTRICTION_STATUS_URL;
    },
    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    newMessagesLabel() {
      const count = this.newMessageCount > 9 ? '9+' : this.newMessageCount;
      const label =
        this.newMessageCount > 1
          ? 'CONVERSATION.NEW_MESSAGES'
          : 'CONVERSATION.NEW_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
  },

  watch: {
    isCampaignHistoryReady(ready) {
      if (!ready) return;
      this.onScrollToMessage({ messageId: this.$route.query.messageId });
    },
    visibleCampaignHistory() {
      if (!this.conversationPanel) return;
      const conversationId = this.currentChat.id;
      const restoreAnchor = captureTimelineAnchor(
        this.conversationPanel,
        this.$route.query.messageId
      );
      this.$nextTick(() => {
        if (this.currentChat.id !== conversationId) return;
        if (!this.hasUserScrolled && !this.$route.query.messageId) {
          this.scrollToBottom();
        } else {
          restoreAnchor();
        }
      });
    },
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      this.fetchAllAttachmentsFromCurrentChat();
      this.newMessageCount = 0;
      this.isNearBottom = true;
      this.messageGapLoadRequestId += 1;
      this.isMessageGapLoading = false;
      this.resetReplyEditorHeight();
    },
    'currentChat.messageGapBeforeId'(newGapBeforeId, oldGapBeforeId) {
      if (
        this.isMessageGapLoading &&
        Number(newGapBeforeId) !== Number(oldGapBeforeId)
      ) {
        this.messageGapLoadRequestId += 1;
        this.isMessageGapLoading = false;
      }
    },
    // The link is appended once the neighbours arrive, below an already scrolled list.
    newerConversation(conversation) {
      if (!conversation) return;
      this.$nextTick(() => {
        if (!this.$route.query.messageId && !this.hasUserScrolled) {
          this.scrollToBottom();
        }
      });
    },
  },

  created() {
    this.currentScrollTarget = null;
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    emitter.on(BUS_EVENTS.MESSAGE_ADDED, this.onMessageAdded);
    // Anything that wants to write must bring the folded editor back first.
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.showReplyBox);
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, this.showReplyBox);
    emitter.on(CMD_AI_ASSIST, this.showReplyBox);
  },

  mounted() {
    this.addScrollListener();
    this.fetchAllAttachmentsFromCurrentChat();
  },

  unmounted() {
    this.removeBusListeners();
    this.removeScrollListener();
  },

  methods: {
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    removeBusListeners() {
      this.currentScrollTarget = null;
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
      emitter.off(BUS_EVENTS.MESSAGE_ADDED, this.onMessageAdded);
      emitter.off(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.showReplyBox);
      emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, this.showReplyBox);
      emitter.off(CMD_AI_ASSIST, this.showReplyBox);
    },
    // a message arrived on its own (not an action the agent took). Only follow it
    // when the agent is already at the bottom, otherwise surface the pill instead
    // of yanking them away from what they are reading.
    onMessageAdded({ message } = {}) {
      if (this.isNearBottom) {
        this.makeMessagesRead();
        this.$nextTick(() => this.scrollToBottom());
        return;
      }
      // activity lines (resolved, assigned, labelled) are not messages someone sent
      if (message && message.message_type !== MESSAGE_TYPE.ACTIVITY) {
        this.newMessageCount += 1;
      }
    },
    onScrollToBottomClick() {
      this.makeMessagesRead();
      this.scrollToBottom();
    },
    updateNearBottom() {
      const el = this.conversationPanel;
      if (!el) return;
      this.isNearBottom =
        el.scrollHeight - el.scrollTop - el.clientHeight <
        NEAR_BOTTOM_THRESHOLD;
      if (this.isNearBottom && this.newMessageCount) {
        this.newMessageCount = 0;
        this.makeMessagesRead();
      }
    },
    onScrollToMessage({ messageId = '' } = {}) {
      this.makeMessagesRead();
      if (!messageId) {
        this.$nextTick(() => this.scrollToBottom());
        return;
      }
      const target = String(messageId);
      this.currentScrollTarget = target;
      this.scrollToMessageWithRetry(target, 10);
    },
    scrollToMessageWithRetry(messageId, attemptsLeft) {
      if (this.currentScrollTarget !== messageId) return;
      const el = document.getElementById('message' + messageId);
      if (el) {
        this.isProgrammaticScroll = true;
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        return;
      }
      if (attemptsLeft <= 0) return;
      requestAnimationFrame(() =>
        this.scrollToMessageWithRetry(messageId, attemptsLeft - 1)
      );
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.lastScrollTop = this.conversationPanel.scrollTop;
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
      clearTimeout(this.programmaticScrollTimer);
    },
    scrollToBottom() {
      this.isProgrammaticScroll = true;
      this.conversationPanel.scrollTop = this.conversationPanel.scrollHeight;
      this.isNearBottom = true;
      this.newMessageCount = 0;
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          const heightDifference =
            this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    isMessageGapNearViewport() {
      const gap = this.conversationPanel.querySelector('[data-message-gap]');
      if (!gap) return false;

      const panelRect = this.conversationPanel.getBoundingClientRect();
      const gapRect = gap.getBoundingClientRect();
      return (
        gapRect.bottom >= panelRect.top &&
        gapRect.top - panelRect.bottom < MESSAGE_GAP_SCROLL_THRESHOLD
      );
    },

    async loadMessageGap() {
      const beforeId = this.currentChat.messageGapBeforeId;
      if (!beforeId || this.isMessageGapLoading) return;

      const gapIndex = this.currentChat.messages.findIndex(
        message => Number(message.id) === Number(beforeId)
      );
      if (gapIndex <= 0) return;

      const conversationId = this.currentChat.id;
      const afterId = this.currentChat.messages[gapIndex - 1].id;
      const requestId = this.messageGapLoadRequestId + 1;
      this.messageGapLoadRequestId = requestId;
      this.isMessageGapLoading = true;

      try {
        await this.$store.dispatch('loadConversationMessageGap', {
          conversationId,
          afterId,
          beforeId,
        });
      } catch (error) {
        // Keep the gap marker available so the next downward scroll can retry.
      } finally {
        if (
          this.messageGapLoadRequestId === requestId &&
          Number(this.currentChat.id) === Number(conversationId)
        ) {
          this.isMessageGapLoading = false;
        }
      }
    },

    handleScroll(e) {
      const { scrollTop } = e.target;
      const isScrollingDown = scrollTop > this.lastScrollTop;
      this.lastScrollTop = scrollTop;
      this.updateNearBottom();
      if (this.isProgrammaticScroll) {
        this.hasUserScrolled = false;
        // A smooth scrollIntoView fires scroll events for the duration of its
        // animation. Only clear the flag once those events go quiet, so the
        // in-flight animation isn't mistaken for a user scroll and doesn't
        // race with a previous-messages fetch adjusting scrollTop mid-animation.
        clearTimeout(this.programmaticScrollTimer);
        this.programmaticScrollTimer = setTimeout(() => {
          this.isProgrammaticScroll = false;
        }, 150);
      } else {
        this.hasUserScrolled = true;
        if (isScrollingDown && this.isMessageGapNearViewport()) {
          this.loadMessageGap();
        }
        this.fetchPreviousMessages(scrollTop);
      }
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);
    },

    makeMessagesRead() {
      this.$store.dispatch('markMessagesRead', { id: this.currentChat.id });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
  >
    <div ref="topBannerRef">
      <Banner
        v-if="isInstagramRestrictionBannerVisible"
        color-scheme="warning"
        class="mx-2 mt-2 min-h-12 !h-auto rounded-lg"
        :banner-message="$t('CONVERSATION.INSTAGRAM_RESTRICTION_BANNER')"
        :href-link="instagramRestrictionStatusUrl"
        :href-link-text="$t('CONVERSATION.INSTAGRAM_RESTRICTION_STATUS_LINK')"
      />
      <Banner
        v-if="!currentChat.can_reply"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
      />
      <Banner
        v-if="hasDuplicateInstagramInbox"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 transition-[padding]"
      :class="[foldMotion, isReplyFolded ? 'pb-16' : 'pb-4']"
      :current-user-id="currentUserId"
      :first-unread-id="unReadMessages[0]?.id"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :messages="timelineMessages"
      :campaign-history="visibleCampaignHistory"
      :conversation-search-query="conversationSearchQuery"
      :active-conversation-search-result-id="activeConversationSearchResultId"
      :is-message-gap-loading="isMessageGapLoading"
      @retry="handleMessageRetry"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
        <ContactConversationLink
          v-if="olderConversation && listLoadingStatus"
          direction="older"
          :conversation="olderConversation"
          :to="
            buildConversationPath(olderConversation.id, {
              keepFolderScope: false,
            })
          "
          @navigate="openConversation(olderConversation)"
        />
        <ReferralBubble v-if="referralData" :referral="referralData" />
        <li v-if="hasMoreCampaignHistory" class="flex justify-center py-3">
          <NextButton
            :label="$t('CAMPAIGN.HISTORY.LOAD_MORE')"
            :disabled="isCampaignHistoryLoading"
            sm
            ghost
            @click="loadCampaignHistory"
          />
        </li>
      </template>
      <template #unreadBadge>
        <li
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ContactConversationLink
          v-if="newerConversation"
          direction="newer"
          :conversation="newerConversation"
          :to="
            buildConversationPath(newerConversation.id, {
              keepFolderScope: false,
            })
          "
          @navigate="openConversation(newerConversation)"
        />
      </template>
    </MessageList>
    <div class="flex relative flex-col bg-n-surface-1">
      <div
        class="absolute left-0 bottom-full flex flex-col items-center w-full gap-1 pointer-events-none"
        :class="isReplyFolded ? 'pb-16' : 'pb-1'"
      >
        <button
          v-if="newMessageCount"
          class="flex items-center gap-1.5 px-2.5 py-1.5 mx-auto text-xs font-medium text-white rounded-full shadow-lg pointer-events-auto bg-n-brand"
          @click="onScrollToBottomClick"
        >
          <i class="i-lucide-arrow-down size-3" />
          {{ newMessagesLabel }}
        </button>
        <div
          v-if="isAnyoneTyping"
          class="flex py-2 pr-4 pl-5 mx-auto text-xs font-semibold bg-white rounded-full shadow-md dark:bg-n-solid-3 text-n-slate-11"
        >
          {{ typingUserNames }}
          <img
            class="w-6 ltr:ml-2 rtl:mr-2"
            src="assets/images/typing.gif"
            alt="Someone is typing"
          />
        </div>
      </div>
      <button
        v-if="!isNearBottom"
        :title="$t('CONVERSATION.SCROLL_TO_BOTTOM')"
        :aria-label="$t('CONVERSATION.SCROLL_TO_BOTTOM')"
        class="absolute z-10 flex items-center justify-center border rounded-full shadow-lg right-4 bottom-full size-9 bg-n-solid-3 hover:bg-n-solid-2 text-n-slate-12 border-n-weak"
        :class="isReplyFolded ? 'mb-20' : 'mb-3'"
        @click="onScrollToBottomClick"
      >
        <i class="i-lucide-arrow-down size-4" />
      </button>
      <Transition v-bind="foldTransition">
        <div
          v-if="isReplyFolded"
          class="absolute inset-x-0 bottom-0 z-10 grid grid-rows-[var(--fold-rows,1fr)]"
        >
          <div class="min-h-0 min-w-0">
            <CollapsedReplyBar
              class="m-2"
              :reply-label="
                isReadingHistory
                  ? $t('CONVERSATION.CONTACT_HISTORY.REPLY_TO_OLDER')
                  : $t('CONVERSATION.REPLYBOX.REPLY')
              "
              :has-latest="isReadingHistory && Boolean(latestConversation)"
              :can-reply="canSendPublicReply"
              @open="revealReplyBox"
              @go-to-latest="openConversation(latestConversation)"
            />
          </div>
        </div>
      </Transition>
      <Transition v-bind="foldTransition">
        <div
          v-show="!isReplyFolded"
          class="grid grid-rows-[var(--fold-rows,1fr)]"
        >
          <div class="min-h-0 min-w-0">
            <ResizableEditorWrapper
              ref="resizableEditorWrapperRef"
              :container-height="Math.max(0, containerHeight - topBannerHeight)"
              :is-an-email-channel="isAnEmailChannel"
              @collapse="collapseReplyBox"
            >
              <ReplyBox
                ref="replyBoxRef"
                @toggle-editor-size="toggleReplyEditorSize"
              />
            </ResizableEditorWrapper>
          </div>
        </div>
      </Transition>
    </div>
  </div>
</template>
