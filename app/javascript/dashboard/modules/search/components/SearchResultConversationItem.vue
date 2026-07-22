<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { isToday, isYesterday, fromUnixTime } from 'date-fns';
import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { messageStamp, dateFormat } from 'shared/helpers/timeHelper';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants.js';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  id: {
    type: Number,
    default: 0,
  },
  name: {
    type: String,
    default: '',
  },
  thumbnail: {
    type: String,
    default: '',
  },
  accountId: {
    type: [String, Number],
    default: '',
  },
  lastActivityAt: {
    type: Number,
    default: 0,
  },
  message: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const navigateTo = computed(() =>
  frontendURL(`accounts/${props.accountId}/conversations/${props.id}`)
);

const previewMessage = computed(() => props.message || {});

const previewTime = computed(() => {
  const timestamp = previewMessage.value.createdAt || props.lastActivityAt;
  if (!timestamp) return '';

  const date = fromUnixTime(timestamp);
  if (isToday(date)) return messageStamp(timestamp, 'HH:mm');
  if (isYesterday(date)) return t('SEARCH.YESTERDAY');
  return dateFormat(timestamp, 'dd/MM/yyyy');
});

const attachmentLabels = computed(() => ({
  [ATTACHMENT_TYPES.IMAGE]: t('SEARCH.PREVIEW_ATTACHMENT.IMAGE'),
  [ATTACHMENT_TYPES.AUDIO]: t('SEARCH.PREVIEW_ATTACHMENT.AUDIO'),
  [ATTACHMENT_TYPES.VIDEO]: t('SEARCH.PREVIEW_ATTACHMENT.VIDEO'),
  [ATTACHMENT_TYPES.FILE]: t('SEARCH.PREVIEW_ATTACHMENT.FILE'),
  [ATTACHMENT_TYPES.LOCATION]: t('SEARCH.PREVIEW_ATTACHMENT.LOCATION'),
  [ATTACHMENT_TYPES.FALLBACK]: t('SEARCH.PREVIEW_ATTACHMENT.LINK'),
  [ATTACHMENT_TYPES.SHARE]: t('SEARCH.PREVIEW_ATTACHMENT.SHARED_CONTENT'),
  [ATTACHMENT_TYPES.CONTACT]: t('SEARCH.PREVIEW_ATTACHMENT.CONTACT'),
  [ATTACHMENT_TYPES.STORY_MENTION]: t(
    'SEARCH.PREVIEW_ATTACHMENT.STORY_MENTION'
  ),
  [ATTACHMENT_TYPES.IG_REEL]: t('SEARCH.PREVIEW_ATTACHMENT.INSTAGRAM_REEL'),
  [ATTACHMENT_TYPES.IG_POST]: t('SEARCH.PREVIEW_ATTACHMENT.INSTAGRAM_POST'),
  [ATTACHMENT_TYPES.IG_STORY]: t('SEARCH.PREVIEW_ATTACHMENT.INSTAGRAM_STORY'),
  [ATTACHMENT_TYPES.EMBED]: t('SEARCH.PREVIEW_ATTACHMENT.EMBED'),
}));

const previewText = computed(() => {
  const { content, contentAttributes, attachments = [] } = previewMessage.value;
  if (content) {
    return content;
  }

  const emailSubject = contentAttributes?.email?.subject;
  if (emailSubject) {
    return emailSubject;
  }

  const [attachment] = attachments;
  if (!attachment) {
    return '';
  }

  if (attachment.fileType === ATTACHMENT_TYPES.FILE) {
    return (
      attachment.extension?.toUpperCase() || t('SEARCH.PREVIEW_ATTACHMENT.FILE')
    );
  }

  return (
    attachmentLabels.value[attachment.fileType] ||
    t('SEARCH.PREVIEW_ATTACHMENT.FILE')
  );
});

const isOutgoingMessage = computed(() => {
  const messageType = previewMessage.value.messageType;
  return messageType !== undefined && messageType !== MESSAGE_TYPE.INCOMING;
});
</script>

<template>
  <router-link :to="navigateTo" class="block w-full min-w-0">
    <CardLayout
      layout="col"
      class="[&>div]:px-3 [&>div]:py-2.5 [&>div]:gap-2 hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <div class="flex items-center gap-2.5 min-w-0 w-full">
        <Avatar
          :name="name"
          :src="thumbnail"
          :size="28"
          rounded-full
          class="flex-shrink-0"
        />
        <div class="min-w-0 flex flex-col gap-2 flex-1">
          <div class="flex items-start justify-between gap-3 min-w-0 w-full">
            <h5
              class="m-0 text-sm font-medium truncate min-w-0 text-n-slate-12 flex-1"
            >
              {{ name }}
            </h5>
            <span
              v-if="previewTime"
              class="text-xs leading-4 flex-shrink-0 text-n-slate-11 whitespace-nowrap"
            >
              {{ previewTime }}
            </span>
          </div>
          <div
            class="flex items-center gap-1.5 min-w-0 w-full text-sm text-n-slate-11"
          >
            <Icon
              v-if="isOutgoingMessage"
              icon="i-lucide-check-check"
              class="size-3.5 flex-shrink-0 text-n-slate-11"
            />
            <span class="truncate min-w-0 text-n-slate-11">
              {{ previewText }}
            </span>
          </div>
          <slot />
        </div>
      </div>
    </CardLayout>
  </router-link>
</template>
