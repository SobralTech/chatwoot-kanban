<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
  // Render without the variant background/rounding (used for stickers, which
  // are transparent and should float without a colored bubble behind them).
  bare: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  isOwnMessage,
  contentAttributes,
} = useMessageContext();
const { t } = useI18n();

// WAHA tags every group message with the participant who actually sent it
// (contentAttributes.sender_name/participant_phone) — the "sender" on the
// message itself is the group contact, not the individual member.
const groupSenderLabel = computed(() => {
  const name = contentAttributes.value?.sender_name;
  if (!name) return '';

  return t('CONVERSATION.WAHA_GROUP_SENDER', {
    name,
    phone: contentAttributes.value.participant_phone,
  });
});

// Other agents' bubbles use a deeper step on the same blue scale so they
// read darker in light mode and lighter in dark mode than the current
// user's own messages (which keep the default n-solid-blue).
const otherAgentBubbleClass = 'bg-n-blue-6 text-n-slate-12';

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-solid-blue text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-tl-sm rtl:rounded-tr-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-tr-sm rtl:rounded-tl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

// When this bubble is followed immediately by another bubble from the same
// group, flatten the bottom corner so the stack reads as one continuous shape.
const groupedCornerMap = {
  [ORIENTATION.LEFT]: 'ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]: 'ltr:rounded-br-sm rtl:rounded-bl-sm',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  if (props.bare) return [];

  const classToApply = [
    variant.value === MESSAGE_VARIANTS.AGENT && !isOwnMessage.value
      ? otherAgentBubbleClass
      : varaintBaseMap[variant.value],
  ];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
    if (shouldGroupWithNext.value) {
      classToApply.push(groupedCornerMap[orientation.value]);
    }
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

// A ghost quote is a snapshot of a message that isn't in this conversation
// (pre-inbox or cross-conversation) — there is nothing to scroll to.
const isGhostQuote = computed(() => Boolean(inReplyTo.value?.isGhost));

const scrollToMessage = () => {
  if (isGhostQuote.value) return;

  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments, mediaType } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;

  const fileType =
    mediaType ??
    (attachments?.length
      ? (attachments[0].fileType ?? attachments[0].file_type)
      : null);
  if (fileType) return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg bg-n-alpha-black1"
      :class="{ 'cursor-pointer': !isGhostQuote }"
      @click="scrollToMessage"
    >
      <div
        v-if="isGhostQuote && inReplyTo.authorName"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ inReplyTo.authorName }}
      </div>
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <div
      v-if="groupSenderLabel"
      class="text-xs font-medium text-n-slate-11 mb-1"
    >
      {{ groupSenderLabel }}
    </div>
    <slot />
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        flexOrientationClass,
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
        variant === MESSAGE_VARIANTS.PRIVATE
          ? 'text-n-amber-12/50'
          : 'text-n-slate-11',
      ]"
      class="mt-2"
    />
  </div>
</template>
