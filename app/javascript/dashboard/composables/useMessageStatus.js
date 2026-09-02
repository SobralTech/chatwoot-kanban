import { computed, toValue } from 'vue';
import { useInbox } from 'dashboard/composables/useInbox';
import {
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from 'dashboard/components-next/message/constants';

/**
 * Resolves the delivery status indicator for a message.
 *
 * Every channel reports delivery differently, so the raw `status` on the
 * message is only meaningful once paired with the inbox it was sent through.
 *
 * @param {Object} message - Reactive sources for the message fields
 * @param {import('vue').MaybeRefOrGetter<string>} message.status
 * @param {import('vue').MaybeRefOrGetter<boolean>} message.isPrivate
 * @param {import('vue').MaybeRefOrGetter<number>} message.messageType
 * @param {import('vue').MaybeRefOrGetter<string|null>} message.sourceId
 * @param {import('vue').MaybeRefOrGetter<Object>} message.contentAttributes
 * @param {import('vue').MaybeRefOrGetter<number|null>} inboxId - Inbox the
 * message belongs to, defaults to the current chat's inbox
 * @returns {{ showStatusIndicator: import('vue').ComputedRef<boolean>, statusToShow: import('vue').ComputedRef<string> }}
 */
export const useMessageStatus = (
  { status, isPrivate, messageType, sourceId, contentAttributes },
  inboxId = null
) => {
  const {
    isAFacebookInbox,
    isALineChannel,
    isAPIInbox,
    isASmsInbox,
    isATelegramChannel,
    isATwilioChannel,
    isAWebWidgetInbox,
    isAWhatsAppChannel,
    isAnEmailChannel,
    isAnInstagramChannel,
    isATiktokChannel,
    isAWahaChannel,
  } = useInbox(inboxId);

  const isOutgoingMessage = computed(() => {
    if (toValue(isPrivate)) return false;
    if (toValue(contentAttributes)?.deleted) return false;

    return [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE].includes(
      toValue(messageType)
    );
  });

  const hasFailed = computed(() => {
    return isOutgoingMessage.value && toValue(status) === MESSAGE_STATUS.FAILED;
  });

  const isSent = computed(() => {
    if (!isOutgoingMessage.value) return false;

    // Messages will be marked as sent for the Email channel if they have a source ID.
    if (isAnEmailChannel.value) return !!toValue(sourceId);

    if (
      isAWhatsAppChannel.value ||
      isAWahaChannel.value ||
      isATwilioChannel.value ||
      isAFacebookInbox.value ||
      isASmsInbox.value ||
      isATelegramChannel.value ||
      isAnInstagramChannel.value ||
      isATiktokChannel.value
    ) {
      return toValue(sourceId) && toValue(status) === MESSAGE_STATUS.SENT;
    }

    // API inbox messages use real sent/delivered/read status values from the external system.
    if (isAPIInbox.value) return toValue(status) === MESSAGE_STATUS.SENT;

    // All messages will be mark as sent for the Line channel, as there is no source ID.
    if (isALineChannel.value) return true;

    return false;
  });

  const isDelivered = computed(() => {
    if (!isOutgoingMessage.value) return false;

    if (
      isAWhatsAppChannel.value ||
      isAWahaChannel.value ||
      isATwilioChannel.value ||
      isASmsInbox.value ||
      isAFacebookInbox.value ||
      isAnInstagramChannel.value ||
      isATiktokChannel.value
    ) {
      return toValue(sourceId) && toValue(status) === MESSAGE_STATUS.DELIVERED;
    }
    // API inbox messages use real delivered status from the external system.
    if (isAPIInbox.value) return toValue(status) === MESSAGE_STATUS.DELIVERED;
    // All messages marked as delivered for the web widget inbox once they are sent.
    if (isAWebWidgetInbox.value) {
      return toValue(status) === MESSAGE_STATUS.SENT;
    }
    if (isALineChannel.value) {
      return toValue(status) === MESSAGE_STATUS.DELIVERED;
    }

    return false;
  });

  const isRead = computed(() => {
    if (!isOutgoingMessage.value) return false;

    if (
      isAWhatsAppChannel.value ||
      isAWahaChannel.value ||
      isATwilioChannel.value ||
      isAFacebookInbox.value ||
      isAnInstagramChannel.value ||
      isATiktokChannel.value
    ) {
      return toValue(sourceId) && toValue(status) === MESSAGE_STATUS.READ;
    }

    if (isAWebWidgetInbox.value || isAPIInbox.value) {
      return toValue(status) === MESSAGE_STATUS.READ;
    }

    return false;
  });

  const statusToShow = computed(() => {
    if (hasFailed.value) return MESSAGE_STATUS.FAILED;
    if (isRead.value) return MESSAGE_STATUS.READ;
    if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
    if (isSent.value) return MESSAGE_STATUS.SENT;

    return MESSAGE_STATUS.PROGRESS;
  });

  return {
    showStatusIndicator: isOutgoingMessage,
    hasFailed,
    statusToShow,
  };
};
