<script setup>
import { computed, onUnmounted } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

import {
  CMD_MUTE_CONVERSATION,
  CMD_PIN_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
  CMD_UNPIN_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);

const currentChat = computed(() => store.getters.getSelectedChat);

const isNotificationsMuted = computed(
  () => !!currentChat.value.additional_attributes?.notifications_muted
);

const isPinned = computed(() => !!currentChat.value.account_pinned_at);

const actionMenuItems = computed(() => {
  const items = [];

  if (!isNotificationsMuted.value) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.MUTE_NOTIFICATIONS'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.UNMUTE_NOTIFICATIONS'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  if (!isPinned.value) {
    items.push({
      icon: 'i-lucide-pin',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.PIN_CONVERSATION'),
      action: 'pin',
      value: 'pin',
    });
  } else {
    items.push({
      icon: 'i-lucide-pin-off',
      label: t('CONVERSATION.CARD_CONTEXT_MENU.UNPIN_CONVERSATION'),
      action: 'unpin',
      value: 'unpin',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return items;
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

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'mute' || action === 'unmute') {
    toggleNotificationsMute();
  } else if (action === 'pin' || action === 'unpin') {
    togglePin();
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
};

emitter.on(CMD_MUTE_CONVERSATION, toggleNotificationsMute);
emitter.on(CMD_UNMUTE_CONVERSATION, toggleNotificationsMute);
emitter.on(CMD_PIN_CONVERSATION, togglePin);
emitter.on(CMD_UNPIN_CONVERSATION, togglePin);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, toggleNotificationsMute);
  emitter.off(CMD_UNMUTE_CONVERSATION, toggleNotificationsMute);
  emitter.off(CMD_PIN_CONVERSATION, togglePin);
  emitter.off(CMD_UNPIN_CONVERSATION, togglePin);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
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
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
