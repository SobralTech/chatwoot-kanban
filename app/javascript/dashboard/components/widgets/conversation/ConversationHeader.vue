<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import ConversationCallButton from './ConversationCallButton.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});
const emit = defineEmits(['openConversationSearch', 'toggleContactDetails']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();
const { uiSettings, updateUISettings } = useUISettings();
const headerSeparator = '\u2022';

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const toggleContactDetails = () => {
  const shouldOpenContactDetails = !uiSettings.value.is_contact_sidebar_open;
  const nextUISettings = {
    is_contact_sidebar_open: shouldOpenContactDetails,
  };

  if (shouldOpenContactDetails) {
    nextUISettings.is_copilot_panel_open = false;
  }

  updateUISettings(nextUISettings);
  emit('toggleContactDetails', shouldOpenContactDetails);
};
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-row items-center justify-between flex-1 w-full min-w-0 gap-3 px-3 py-2 min-h-12"
  >
    <div class="flex items-center justify-start flex-1 min-w-0">
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        icon-only
        class="ltr:mr-2 rtl:ml-2"
      />
      <div
        role="button"
        tabindex="0"
        class="flex items-center flex-1 min-w-0 overflow-hidden rounded-md cursor-pointer group focus:outline-none focus-visible:ring-1 focus-visible:ring-n-brand"
        :aria-label="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_DETAILS')"
        data-testid="conversation-header-contact"
        @click="toggleContactDetails"
        @keydown.enter.prevent="toggleContactDetails"
        @keydown.space.prevent="toggleContactDetails"
      >
        <Avatar
          :name="currentContact.name"
          :src="currentContact.thumbnail"
          :size="32"
          :status="currentContact.availability_status"
          hide-offline-status
          rounded-full
        />
        <div
          class="flex flex-col min-w-0 max-w-full gap-0.5 ml-2 overflow-hidden rtl:ml-0 rtl:mr-2"
          data-testid="conversation-header-contact-name"
        >
          <div class="flex items-center min-w-0 gap-2">
            <span
              class="min-w-0 flex-1 text-base font-medium leading-tight truncate text-n-slate-12 group-hover:text-n-slate-12"
            >
              {{ currentContact.name }}
            </span>
            <fluent-icon
              v-if="!isHMACVerified"
              v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
              size="14"
              class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
              icon="warning"
            />
            <span
              v-if="isSnoozed"
              class="flex-shrink-0 text-xs text-n-slate-11"
            >
              {{ headerSeparator }}
            </span>
            <span
              v-if="isSnoozed"
              class="flex-shrink-0 text-xs font-medium text-n-amber-10"
            >
              {{ snoozedDisplayText }}
            </span>
          </div>
          <InboxName :inbox="inbox" class="!mx-0" />
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-end flex-shrink-0 gap-2 header-actions-wrap"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <ConversationCallButton :inbox="inbox" :chat="currentChat" />
      <NextButton
        v-tooltip="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
        sm
        ghost
        slate
        icon="i-lucide-search"
        :title="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
        :aria-label="$t('CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION')"
        data-testid="conversation-header-search-button"
        @click.stop="emit('openConversationSearch')"
      />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
