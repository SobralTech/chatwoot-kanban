<script>
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { ATTACHMENT_ICONS } from 'shared/constants/messages';

export default {
  name: 'MessagePreview',
  props: {
    message: {
      type: Object,
      required: true,
    },
    showMessageType: {
      type: Boolean,
      default: true,
    },
    defaultEmptyMessage: {
      type: String,
      default: '',
    },
    pinIcon: {
      type: String,
      default: '',
    },
  },
  setup() {
    const { getPlainText } = useMessageFormatter();
    return {
      getPlainText,
    };
  },
  computed: {
    messageByAgent() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.OUTGOING;
    },
    isMessageAnActivity() {
      const { message_type: messageType } = this.message;
      return messageType === MESSAGE_TYPE.ACTIVITY;
    },
    isMessagePrivate() {
      const { private: isPrivate } = this.message;
      return isPrivate;
    },
    parsedLastMessage() {
      const { content_attributes: contentAttributes } = this.message;
      const { email: { subject } = {} } = contentAttributes || {};
      return this.getPlainText(subject || this.message.content);
    },
    lastMessageFileType() {
      const [{ file_type: fileType } = {}] = this.message.attachments;
      return fileType;
    },
    attachmentIcon() {
      return ATTACHMENT_ICONS[this.lastMessageFileType];
    },
    attachmentMessageContent() {
      return `CHAT_LIST.ATTACHMENTS.${this.lastMessageFileType}.CONTENT`;
    },
    isMessageSticker() {
      return this.message && this.message.content_type === 'sticker';
    },
  },
};
</script>

<template>
  <div class="flex items-center min-w-0 overflow-hidden gap-1">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="messageByAgent"
        size="14"
        class="-mt-0.5 text-n-slate-11 flex-shrink-0"
        icon="checkmark-double"
      />
      <fluent-icon
        v-else-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 text-n-slate-11 flex-shrink-0"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 text-n-slate-11 flex-shrink-0"
        icon="info"
      />
    </template>
    <span
      v-if="message.content && isMessageSticker"
      class="flex items-center gap-1 flex-1 min-w-0 truncate"
    >
      <fluent-icon
        size="16"
        class="-mt-0.5 inline-block text-n-slate-11 flex-shrink-0"
        icon="image"
      />
      <span class="truncate">{{
        $t('CHAT_LIST.ATTACHMENTS.image.CONTENT')
      }}</span>
    </span>
    <span v-else-if="message.content" class="flex-1 min-w-0 truncate">
      {{ parsedLastMessage }}
    </span>
    <span
      v-else-if="message.attachments"
      class="flex items-center gap-1 flex-1 min-w-0 truncate"
    >
      <fluent-icon
        v-if="attachmentIcon && showMessageType"
        size="16"
        class="-mt-0.5 inline-block text-n-slate-11 flex-shrink-0"
        :icon="attachmentIcon"
      />
      <span class="truncate">{{ $t(`${attachmentMessageContent}`) }}</span>
    </span>
    <span v-else class="flex-1 min-w-0 truncate">
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
    <fluent-icon
      v-if="pinIcon"
      size="12"
      class="-mt-0.5 text-n-slate-10 flex-shrink-0"
      :icon="pinIcon"
    />
  </div>
</template>
