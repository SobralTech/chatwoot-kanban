<script setup>
import {
  onMounted,
  onBeforeUnmount,
  computed,
  ref,
  toRefs,
  watch,
  nextTick,
} from 'vue';
import { useTimeoutFn } from '@vueuse/core';
import { provideMessageContext } from './provider.js';
import { useTrack } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { LocalStorage } from 'shared/helpers/localStorage';
import { ACCOUNT_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { getInboxIconByType, INBOX_TYPES } from 'dashboard/helper/inbox';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  MESSAGE_TYPES,
  ATTACHMENT_TYPES,
  MESSAGE_VARIANTS,
  SENDER_TYPES,
  ORIENTATION,
  MESSAGE_STATUS,
  CONTENT_TYPES,
} from './constants';

import Avatar from 'next/avatar/Avatar.vue';

import TextBubble from './bubbles/Text/Index.vue';
import ActivityBubble from './bubbles/Activity.vue';
import ImageBubble from './bubbles/Image.vue';
import StickerBubble from './bubbles/Sticker.vue';
import FileBubble from './bubbles/File.vue';
import AudioBubble from './bubbles/Audio.vue';
import VideoBubble from './bubbles/Video.vue';
import EmbedBubble from './bubbles/Embed.vue';
import InstagramStoryBubble from './bubbles/InstagramStory.vue';
import EmailBubble from './bubbles/Email/Index.vue';
import UnsupportedBubble from './bubbles/Unsupported.vue';
import ContactBubble from './bubbles/Contact.vue';
import DyteBubble from './bubbles/Dyte.vue';
import LocationBubble from './bubbles/Location.vue';
import CSATBubble from './bubbles/CSAT.vue';
import FormBubble from './bubbles/Form.vue';
import VoiceCallBubble from './bubbles/VoiceCall.vue';

import MessageError from './MessageError.vue';
import MessageReactions from './MessageReactions.vue';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';
import { useBranding } from 'shared/composables/useBranding';

/**
 * @typedef {Object} Attachment
 * @property {number} id - Unique identifier for the attachment
 * @property {number} messageId - ID of the associated message
 * @property {'image'|'audio'|'video'|'file'|'location'|'fallback'|'share'|'story_mention'|'contact'|'ig_reel'} fileType - Type of the attachment (file or image)
 * @property {number} accountId - ID of the associated account
 * @property {string|null} extension - File extension
 * @property {string} dataUrl - URL to access the full attachment data
 * @property {string} thumbUrl - URL to access the thumbnail version
 * @property {number} fileSize - Size of the file in bytes
 * @property {number|null} width - Width of the image if applicable
 * @property {number|null} height - Height of the image if applicable
 */

/**
 * @typedef {Object} Sender
 * @property {Object} additional_attributes - Additional attributes of the sender
 * @property {Object} custom_attributes - Custom attributes of the sender
 * @property {string} email - Email of the sender
 * @property {number} id - ID of the sender
 * @property {string|null} identifier - Identifier of the sender
 * @property {string} name - Name of the sender
 * @property {string|null} phone_number - Phone number of the sender
 * @property {string} thumbnail - Thumbnail URL of the sender
 * @property {string} type - Type of sender
 */

/**
 * @typedef {Object} ContentAttributes
 * @property {string} externalError - an error message to be shown if the message failed to send
 */

/**
 * @typedef {Object} Props
 * @property {('sent'|'delivered'|'read'|'failed'|'progress')} status - The delivery status of the message
 * @property {ContentAttributes} [contentAttributes={}] - Additional attributes of the message content
 * @property {Attachment[]} [attachments=[]] - The attachments associated with the message
 * @property {Sender|null} [sender=null] - The sender information
 * @property {boolean} [private=false] - Whether the message is private
 * @property {number|null} [senderId=null] - The ID of the sender
 * @property {number} createdAt - Timestamp when the message was created
 * @property {number} currentUserId - The ID of the current user
 * @property {number} id - The unique identifier for the message
 * @property {number} messageType - The type of message (must be one of MESSAGE_TYPES)
 * @property {string|null} [error=null] - Error message if the message failed to send
 * @property {string|null} [senderType=null] - The type of the sender
 * @property {string} content - The message content
 * @property {boolean} [groupWithNext=false] - Whether the message should be grouped with the next message
 * @property {boolean} [groupWithPrevious=false] - Whether the message should be grouped with the previous message
 * @property {Object|null} [inReplyTo=null] - The message to which this message is a reply
 * @property {boolean} [isEmailInbox=false] - Whether the message is from an email inbox
 * @property {number} conversationId - The ID of the conversation to which the message belongs
 * @property {number} inboxId - The ID of the inbox to which the message belongs
 */

// eslint-disable-next-line vue/define-macros-order
const props = defineProps({
  id: { type: Number, required: true },
  messageType: {
    type: Number,
    required: true,
    validator: value => Object.values(MESSAGE_TYPES).includes(value),
  },
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
  attachments: { type: Array, default: () => [] },
  call: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  content: { type: String, default: null },
  contentAttributes: { type: Object, default: () => ({}) },
  contentType: {
    type: String,
    default: 'text',
    validator: value => Object.values(CONTENT_TYPES).includes(value),
  },
  conversationId: { type: Number, required: true },
  createdAt: { type: Number, required: true }, // eslint-disable-line vue/no-unused-properties
  currentUserId: { type: Number, required: true }, // eslint-disable-line vue/no-unused-properties
  groupWithNext: { type: Boolean, default: false },
  groupWithPrevious: { type: Boolean, default: false },
  inboxId: { type: Number, default: null }, // eslint-disable-line vue/no-unused-properties
  inboxSupportsReplyTo: { type: Object, default: () => ({}) },
  inReplyTo: { type: Object, default: null }, // eslint-disable-line vue/no-unused-properties
  isEmailInbox: { type: Boolean, default: false },
  private: { type: Boolean, default: false },
  additionalAttributes: { type: Object, default: () => ({}) },
  sender: { type: Object, default: null },
  senderId: { type: Number, default: null },
  senderType: { type: String, default: null },
  sourceId: { type: String, default: '' },
  conversationSearchQuery: { type: String, default: '' }, // eslint-disable-line vue/no-unused-properties
  activeConversationSearchResultId: { type: Number, default: null },
});

const emit = defineEmits(['retry']);

const contextMenuPosition = ref({});
const isFlashing = ref(false);
const showContextMenu = ref(false);
const { t } = useI18n();
const route = useRoute();
const inboxGetter = useMapGetter('inboxes/getInbox');
const inbox = computed(() => inboxGetter.value(props.inboxId) || {});
const { replaceInstallationName } = useBranding();

/**
 * Computes the message variant based on props
 * @type {import('vue').ComputedRef<'user'|'agent'|'activity'|'private'|'bot'|'template'>}
 */
const variant = computed(() => {
  if (props.private) return MESSAGE_VARIANTS.PRIVATE;

  if (props.isEmailInbox) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) {
      return MESSAGE_VARIANTS.EMAIL;
    }
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return MESSAGE_VARIANTS.EMAIL;
  }

  if (props.status === MESSAGE_STATUS.FAILED) return MESSAGE_VARIANTS.ERROR;
  if (props.contentAttributes?.isUnsupported)
    return MESSAGE_VARIANTS.UNSUPPORTED;

  if (props.contentAttributes?.externalEcho) {
    return MESSAGE_VARIANTS.AGENT;
  }

  const isBot =
    props.sender?.type === SENDER_TYPES.AGENT_BOT ||
    props.senderType === SENDER_TYPES.AGENT_BOT ||
    (!props.sender && !props.additionalAttributes?.senderName);
  if (isBot && props.messageType === MESSAGE_TYPES.OUTGOING) {
    return MESSAGE_VARIANTS.BOT;
  }

  const variants = {
    [MESSAGE_TYPES.INCOMING]: MESSAGE_VARIANTS.USER,
    [MESSAGE_TYPES.ACTIVITY]: MESSAGE_VARIANTS.ACTIVITY,
    [MESSAGE_TYPES.OUTGOING]: MESSAGE_VARIANTS.AGENT,
    [MESSAGE_TYPES.TEMPLATE]: MESSAGE_VARIANTS.TEMPLATE,
  };

  return variants[props.messageType] || MESSAGE_VARIANTS.USER;
});

const isBotOrAgentMessage = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) {
    return false;
  }
  // if an outgoing message is still processing, then it's definitely a
  // message sent by the current user
  if (
    props.status === MESSAGE_STATUS.PROGRESS &&
    props.messageType === MESSAGE_TYPES.OUTGOING
  ) {
    return true;
  }
  const senderId = props.senderId ?? props.sender?.id;
  const senderType = props.sender?.type ?? props.senderType;

  if (!senderType || !senderId) {
    return true;
  }

  if (
    [SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT].includes(
      senderType
    )
  ) {
    return true;
  }

  return senderType.toLowerCase() === SENDER_TYPES.USER.toLowerCase();
});

/**
 * Computes the message orientation based on sender type and message type
 * @returns {import('vue').ComputedRef<'left'|'right'|'center'>} The computed orientation
 */
const orientation = computed(() => {
  if (isBotOrAgentMessage.value) {
    return ORIENTATION.RIGHT;
  }

  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return ORIENTATION.CENTER;

  return ORIENTATION.LEFT;
});

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const gridClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'grid grid-cols-1fr',
    [ORIENTATION.RIGHT]: 'grid grid-cols-[1fr_24px]',
  };

  return map[orientation.value];
});

const gridTemplate = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: `
      "bubble"
      "meta"
    `,
    [ORIENTATION.RIGHT]: `
      "name avatar"
      "bubble avatar"
      "meta spacer"
    `,
  };

  return map[orientation.value];
});

const shouldGroupWithNext = computed(() => {
  if (props.status === MESSAGE_STATUS.FAILED) return false;

  return props.groupWithNext;
});

// Messages sent by the current user shouldn't show an avatar/name, only
// messages sent by other agents or bots should.
const isOwnMessage = computed(() => {
  if (
    props.status === MESSAGE_STATUS.PROGRESS &&
    props.messageType === MESSAGE_TYPES.OUTGOING
  ) {
    return true;
  }

  const senderId = props.senderId ?? props.sender?.id;
  return senderId != null && senderId === props.currentUserId;
});

const shouldShowAvatar = computed(() => {
  if (props.messageType === MESSAGE_TYPES.ACTIVITY) return false;
  if (orientation.value === ORIENTATION.LEFT) return false;
  if (isOwnMessage.value) return false;

  return true;
});

const componentToRender = computed(() => {
  if (props.isEmailInbox && !props.private) {
    const emailInboxTypes = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];
    if (emailInboxTypes.includes(props.messageType)) return EmailBubble;
  }

  if (props.contentType === CONTENT_TYPES.INPUT_CSAT) {
    return CSATBubble;
  }

  if (
    [CONTENT_TYPES.INPUT_SELECT, CONTENT_TYPES.FORM].includes(props.contentType)
  ) {
    return FormBubble;
  }

  if (props.contentType === CONTENT_TYPES.VOICE_CALL) {
    return VoiceCallBubble;
  }

  if (props.contentType === CONTENT_TYPES.INCOMING_EMAIL) {
    return EmailBubble;
  }

  if (props.contentAttributes?.isUnsupported) {
    return UnsupportedBubble;
  }

  if (props.contentAttributes.type === 'dyte') {
    return DyteBubble;
  }

  const instagramSharedTypes = [
    ATTACHMENT_TYPES.STORY_MENTION,
    ATTACHMENT_TYPES.IG_STORY,
    ATTACHMENT_TYPES.IG_STORY_REPLY,
    ATTACHMENT_TYPES.IG_POST,
  ];
  if (instagramSharedTypes.includes(props.contentAttributes.imageType)) {
    return InstagramStoryBubble;
  }

  if (Array.isArray(props.attachments) && props.attachments.length === 1) {
    const fileType = props.attachments[0].fileType;

    // Stickers are stored as image attachments but flagged via content_type so
    // they render in the compact, background-less sticker bubble.
    if (props.contentType === CONTENT_TYPES.STICKER) return StickerBubble;

    if (!props.content) {
      if (fileType === ATTACHMENT_TYPES.IMAGE) return ImageBubble;
      if (fileType === ATTACHMENT_TYPES.FILE) return FileBubble;
      if (fileType === ATTACHMENT_TYPES.AUDIO) return AudioBubble;
      if (fileType === ATTACHMENT_TYPES.VIDEO) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.IG_REEL) return VideoBubble;
      if (fileType === ATTACHMENT_TYPES.EMBED) return EmbedBubble;
      if (fileType === ATTACHMENT_TYPES.LOCATION) return LocationBubble;
    }
    // Attachment content is the name of the contact
    if (fileType === ATTACHMENT_TYPES.CONTACT) return ContactBubble;
  }

  return TextBubble;
});

const shouldShowContextMenu = computed(() => {
  return !props.contentAttributes?.isUnsupported;
});

const isBubble = computed(() => {
  return props.messageType !== MESSAGE_TYPES.ACTIVITY;
});

const isMessageDeleted = computed(() => {
  return props.contentAttributes?.deleted;
});

// A message the contact/agent edited on WhatsApp: kept in place but struck
// through, while the edited version arrives as a new message quoting it.
const isSuperseded = computed(() => {
  return !!props.additionalAttributes?.superseded;
});

// WhatsApp reactions on this message, keyed by reactor. Chips never show on
// deleted messages (WhatsApp drops reactions on revoke) nor on struck-through
// edit-family members (reactions migrate to the current version).
const messageReactions = computed(() => props.contentAttributes?.reactions);
const shouldShowReactions = computed(() => {
  if (isMessageDeleted.value || isSuperseded.value) return false;

  return Object.keys(messageReactions.value || {}).length > 0;
});

const isActiveSearchResult = computed(() => {
  return Number(props.activeConversationSearchResultId) === Number(props.id);
});

const isWahaInbox = computed(() => {
  return inbox.value?.channel_type === INBOX_TYPES.WAHA;
});

// WhatsApp only allows editing within 15 minutes of the original send.
const withinWahaEditWindow = computed(() => {
  const FIFTEEN_MINUTES = 15 * 60;
  return Date.now() / 1000 - props.createdAt < FIFTEEN_MINUTES;
});

const payloadForContextMenu = computed(() => {
  return {
    id: props.id,
    content_attributes: props.contentAttributes,
    content: props.content,
    conversation_id: props.conversationId,
  };
});

const contextMenuEnabledOptions = computed(() => {
  const hasText = !!props.content;
  const hasAttachments = !!(props.attachments && props.attachments.length > 0);

  const isOutgoing = props.messageType === MESSAGE_TYPES.OUTGOING;
  const isFailedOrProcessing =
    props.status === MESSAGE_STATUS.FAILED ||
    props.status === MESSAGE_STATUS.PROGRESS;

  return {
    copy: hasText,
    delete:
      (hasText || hasAttachments) &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
    cannedResponse: isOutgoing && hasText && !isMessageDeleted.value,
    copyLink: !isFailedOrProcessing,
    translate: !isFailedOrProcessing && !isMessageDeleted.value && hasText,
    replyTo:
      !props.private &&
      props.inboxSupportsReplyTo.outgoing &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
    wahaEdit:
      isWahaInbox.value &&
      isOutgoing &&
      hasText &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value &&
      !isSuperseded.value &&
      withinWahaEditWindow.value,
    // WhatsApp allows reacting to any non-deleted message, incoming or
    // outgoing, with no time window.
    wahaReact:
      isWahaInbox.value &&
      !props.private &&
      !!props.sourceId &&
      !isFailedOrProcessing &&
      !isMessageDeleted.value,
  };
});

const shouldRenderMessage = computed(() => {
  const hasAttachments = !!(props.attachments && props.attachments.length > 0);
  const isEmailContentType = props.contentType === CONTENT_TYPES.INCOMING_EMAIL;
  const isUnsupported = props.contentAttributes?.isUnsupported;
  const isAnIntegrationMessage =
    props.contentType === CONTENT_TYPES.INTEGRATIONS;
  const isFailedMessage = props.status === MESSAGE_STATUS.FAILED;
  const hasExternalError = !!props.contentAttributes?.externalError;

  return (
    hasAttachments ||
    props.content ||
    isEmailContentType ||
    isUnsupported ||
    isAnIntegrationMessage ||
    isFailedMessage ||
    hasExternalError
  );
});

function openContextMenu(e) {
  const shouldSkipContextMenu =
    e.target?.classList.contains('skip-context-menu') ||
    ['a', 'img'].includes(e.target?.tagName.toLowerCase());
  if (shouldSkipContextMenu || getSelection().toString()) {
    return;
  }

  e.preventDefault();
  if (e.type === 'contextmenu') {
    useTrack(ACCOUNT_EVENTS.OPEN_MESSAGE_CONTEXT_MENU);
  }
  contextMenuPosition.value = {
    x: e.pageX || e.clientX,
    y: e.pageY || e.clientY,
  };
  showContextMenu.value = true;
}

function closeContextMenu() {
  showContextMenu.value = false;
  contextMenuPosition.value = { x: null, y: null };
}

function handleReplyTo() {
  const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
  const { conversationId, id: replyTo } = props;

  LocalStorage.updateJsonStore(replyStorageKey, conversationId, replyTo);
  emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, props);
}

const avatarInfo = computed(() => {
  if (props.contentAttributes?.externalEcho) {
    const { name, avatar_url, channel_type, medium } = inbox.value;
    const iconName = avatar_url
      ? null
      : getInboxIconByType(channel_type, medium, 'fill', name);
    return {
      name: iconName ? '' : name || t('CONVERSATION.NATIVE_APP'),
      src: avatar_url || '',
      iconName,
    };
  }

  // If no sender, check for Slack (or other integration) sender info
  if (!props.sender) {
    const { senderName, senderAvatarUrl } = props.additionalAttributes || {};
    if (senderName) {
      // Messages mirrored from the WhatsApp app have no agent; show the WhatsApp
      // logo instead of the label's initials (the Avatar prefers iconName over
      // initials, and the name is still used for the label above the bubble).
      const iconName =
        !senderAvatarUrl && inbox.value.channel_type === INBOX_TYPES.WAHA
          ? getInboxIconByType(INBOX_TYPES.WAHA, '', 'fill')
          : null;
      return { name: senderName, src: senderAvatarUrl ?? '', iconName };
    }
    return {
      name: t('CONVERSATION.BOT'),
      src: '',
      iconName: 'i-lucide-bot-message-square',
    };
  }

  const { sender } = props;
  const { name, type, avatarUrl, thumbnail } = sender || {};

  // If sender type is agent bot, use avatarUrl, falling back to a robot icon
  if (type === SENDER_TYPES.AGENT_BOT) {
    return {
      name: name ?? '',
      src: avatarUrl ?? '',
      iconName: 'i-lucide-bot-message-square',
    };
  }

  if (type === SENDER_TYPES.CAPTAIN_ASSISTANT) {
    return {
      name: name ?? '',
      src: avatarUrl ?? '',
    };
  }

  // For all other senders, use thumbnail
  return {
    name: name ?? '',
    src: thumbnail ?? '',
  };
});

const avatarTooltip = computed(() => {
  if (props.contentAttributes?.externalEcho) {
    return replaceInstallationName(t('CONVERSATION.NATIVE_APP_ADVISORY'));
  }
  if (avatarInfo.value.name === '') return '';
  return `${t('CONVERSATION.SENT_BY')} ${avatarInfo.value.name}`;
});

const FLASH_DURATION = 2000;
const { start: startFlashTimer } = useTimeoutFn(
  () => {
    isFlashing.value = false;
  },
  FLASH_DURATION,
  { immediate: false }
);

const flashMessage = () => {
  isFlashing.value = true;
  startFlashTimer();
};

const onScrollToMessage = ({ messageId } = {}) => {
  if (Number(messageId) !== Number(props.id)) return;

  flashMessage();
};

const scrollToActiveSearchResult = () => {
  if (!isActiveSearchResult.value) return;

  flashMessage();
  nextTick(() => {
    const messageElement = document.getElementById(`message${props.id}`);
    messageElement?.scrollIntoView?.({ behavior: 'smooth', block: 'nearest' });
  });
};

onMounted(() => {
  emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, onScrollToMessage);
  if (Number(route.query.messageId) === Number(props.id)) flashMessage();
  scrollToActiveSearchResult();
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, onScrollToMessage);
});

watch(() => props.activeConversationSearchResultId, scrollToActiveSearchResult);

provideMessageContext({
  ...toRefs(props),
  isPrivate: computed(() => props.private),
  variant,
  orientation,
  isBotOrAgentMessage,
  isOwnMessage,
  shouldGroupWithNext,
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="shouldRenderMessage"
    :id="`message${props.id}`"
    class="flex w-full mb-2 message-bubble-container"
    :data-message-id="props.id"
    :class="[
      flexOrientationClass,
      {
        'relative before:absolute before:inset-0 before:rounded-lg before:pointer-events-none before:bg-n-blue-9/30 before:animate-message-flash':
          isFlashing,
      },
    ]"
  >
    <div v-if="variant === MESSAGE_VARIANTS.ACTIVITY">
      <ActivityBubble :content="content" />
    </div>
    <div
      v-else
      :class="[
        gridClass,
        {
          'gap-y-2': contentAttributes.externalError,
          'w-full': variant === MESSAGE_VARIANTS.EMAIL,
        },
      ]"
      class="gap-x-2"
      :style="{
        gridTemplateAreas: gridTemplate,
      }"
    >
      <div
        v-if="!groupWithPrevious && shouldShowAvatar"
        class="[grid-area:name] flex items-center gap-1.5 mb-1 text-xs text-n-slate-11"
        :class="flexOrientationClass"
      >
        {{ avatarInfo.name }}
      </div>
      <div
        v-if="!groupWithPrevious && shouldShowAvatar"
        v-tooltip.left-start="avatarTooltip"
        class="[grid-area:avatar] flex items-start"
      >
        <Avatar v-bind="avatarInfo" :size="24" />
      </div>
      <div
        class="[grid-area:bubble] flex"
        :class="{
          'ltr:ml-8 rtl:mr-8 justify-end': orientation === ORIENTATION.RIGHT,
          'ltr:mr-8 rtl:ml-8': orientation === ORIENTATION.LEFT,
          'min-w-0': variant === MESSAGE_VARIANTS.EMAIL,
          'line-through opacity-70': isSuperseded,
        }"
        @contextmenu="openContextMenu($event)"
      >
        <Component :is="componentToRender" />
      </div>
      <MessageReactions
        v-if="shouldShowReactions"
        class="[grid-area:meta] relative z-10 -mt-2"
        :class="[
          flexOrientationClass,
          orientation === ORIENTATION.RIGHT
            ? 'ltr:pr-2 rtl:pl-2'
            : 'ltr:pl-2 rtl:pr-2',
        ]"
        :reactions="messageReactions"
        :message-id="id"
        :conversation-id="conversationId"
      />
      <MessageError
        v-if="contentAttributes.externalError"
        class="[grid-area:meta]"
        :class="flexOrientationClass"
        :error="contentAttributes.externalError"
        @retry="emit('retry')"
      />
    </div>
    <div v-if="shouldShowContextMenu" class="context-menu-wrap">
      <ContextMenu
        v-if="isBubble"
        :context-menu-position="contextMenuPosition"
        :is-open="showContextMenu"
        :enabled-options="contextMenuEnabledOptions"
        :message="payloadForContextMenu"
        hide-button
        @open="openContextMenu"
        @close="closeContextMenu"
        @reply-to="handleReplyTo"
      />
    </div>
  </div>
</template>
