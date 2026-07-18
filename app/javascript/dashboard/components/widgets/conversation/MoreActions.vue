<script setup>
import { computed, ref, onUnmounted } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import wootConstants from 'dashboard/constants/globals';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_PIN_CONVERSATION,
  CMD_REOPEN_CONVERSATION,
  CMD_RESOLVE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
  CMD_UNPIN_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();
const { checkMissingAttributes } = useConversationRequiredAttributes();

const resolveAttributesModalRef = ref(null);

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);

const currentChat = computed(() => store.getters.getSelectedChat);

const isNotificationsMuted = computed(
  () => !!currentChat.value.additional_attributes?.notifications_muted
);

const isPinned = computed(() => !!currentChat.value.account_pinned_at);

const isOpen = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.OPEN
);
const isResolved = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.RESOLVED
);
const showOpenButton = computed(
  () =>
    currentChat.value.status === wootConstants.STATUS_TYPE.PENDING ||
    currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const actionMenuSections = computed(() => {
  const statusItems = [];

  if (isOpen.value) {
    statusItems.push({
      icon: 'i-lucide-check',
      label: t('CONVERSATION.HEADER.RESOLVE_ACTION'),
      action: 'resolve',
      value: 'resolve',
    });
  } else if (isResolved.value) {
    statusItems.push({
      icon: 'i-lucide-rotate-ccw',
      label: t('CONVERSATION.HEADER.REOPEN_ACTION'),
      action: 'open',
      value: 'open',
    });
  } else if (showOpenButton.value) {
    statusItems.push({
      icon: 'i-lucide-rotate-ccw',
      label: t('CONVERSATION.HEADER.OPEN_ACTION'),
      action: 'open',
      value: 'open',
    });
  }

  const otherItems = [];

  if (!isNotificationsMuted.value) {
    otherItems.push({
      icon: 'i-lucide-volume-off',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.MUTE_NOTIFICATIONS'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    otherItems.push({
      icon: 'i-lucide-volume-1',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.UNMUTE_NOTIFICATIONS'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  if (!isPinned.value) {
    otherItems.push({
      icon: 'i-lucide-pin',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.PIN_CONVERSATION'),
      action: 'pin',
      value: 'pin',
    });
  } else {
    otherItems.push({
      icon: 'i-lucide-pin-off',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.UNPIN_CONVERSATION'),
      action: 'unpin',
      value: 'unpin',
    });
  }

  otherItems.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return [{ items: statusItems }, { items: otherItems }];
});

// This function is needed for the event listeners
const toggleNotificationsMute = () => {
  const wasMuted = isNotificationsMuted.value;
  store.dispatch('toggleConversationNotificationsMute', {
    conversationId: currentChat.value.id,
  });
  useAlert(
    wasMuted
      ? t('CONVERSATION.CARD_CONTEXT_MENU.UNMUTE_NOTIFICATIONS_SUCCESS')
      : t('CONVERSATION.CARD_CONTEXT_MENU.MUTE_NOTIFICATIONS_SUCCESS')
  );
};

// This function is needed for the event listeners
const togglePin = () => {
  store.dispatch('toggleConversationPin', {
    conversationId: currentChat.value.id,
  });
};

const toggleStatus = (status, snoozedUntil, customAttributes = null) => {
  const payload = {
    conversationId: currentChat.value.id,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
};

const handleResolveWithAttributes = ({ attributes, context }) => {
  if (context) {
    const currentCustomAttributes = currentChat.value.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };
    toggleStatus(
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
};

// This function is needed for the event listeners
const onCmdOpenConversation = () => {
  toggleStatus(wootConstants.STATUS_TYPE.OPEN);
};

// This function is needed for the event listeners
const onCmdResolveConversation = () => {
  const currentCustomAttributes = currentChat.value.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    const conversationContext = {
      id: currentChat.value.id,
      snoozedUntil: null,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleStatus(wootConstants.STATUS_TYPE.RESOLVED);
  }
};

const getConversationParams = () => {
  const allConversations = document.querySelectorAll(
    '.conversations-list .conversation'
  );

  const activeConversation = document.querySelector(
    'div.conversations-list div.conversation.active'
  );
  const activeConversationIndex = [...allConversations].indexOf(
    activeConversation
  );
  const lastConversationIndex = allConversations.length - 1;

  return {
    all: allConversations,
    activeIndex: activeConversationIndex,
    lastIndex: lastConversationIndex,
  };
};

const keyboardEvents = {
  'Alt+KeyE': {
    action: async () => {
      onCmdResolveConversation();
    },
  },
  '$mod+Alt+KeyE': {
    action: async event => {
      const { all, activeIndex, lastIndex } = getConversationParams();
      onCmdResolveConversation();

      if (activeIndex < lastIndex) {
        all[activeIndex + 1].click();
      } else if (all.length > 1) {
        all[0].click();
        document.querySelector('.conversations-list').scrollTop = 0;
      }
      event.preventDefault();
    },
  },
};

useKeyboardEvents(keyboardEvents);

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute' || action === 'unmute') {
    toggleNotificationsMute();
  } else if (action === 'pin' || action === 'unpin') {
    togglePin();
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  } else if (action === 'resolve') {
    onCmdResolveConversation();
  } else if (action === 'open') {
    onCmdOpenConversation();
  }
};

emitter.on(CMD_MUTE_CONVERSATION, toggleNotificationsMute);
emitter.on(CMD_UNMUTE_CONVERSATION, toggleNotificationsMute);
emitter.on(CMD_PIN_CONVERSATION, togglePin);
emitter.on(CMD_UNPIN_CONVERSATION, togglePin);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);
emitter.on(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
emitter.on(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, toggleNotificationsMute);
  emitter.off(CMD_UNMUTE_CONVERSATION, toggleNotificationsMute);
  emitter.off(CMD_PIN_CONVERSATION, togglePin);
  emitter.off(CMD_UNPIN_CONVERSATION, togglePin);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
  emitter.off(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
  emitter.off(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-md group-hover:bg-n-alpha-2"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-sections="actionMenuSections"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
