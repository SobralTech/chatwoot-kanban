<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { isToday, isYesterday, fromUnixTime } from 'date-fns';
import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { messageStamp, dateFormat } from 'shared/helpers/timeHelper';
import { MESSAGE_TYPE } from 'shared/constants/messages';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  id: {
    type: Number,
    default: 0,
  },
  accountId: {
    type: [String, Number],
    default: '',
  },
  createdAt: {
    type: [String, Date, Number],
    default: '',
  },
  messageId: {
    type: Number,
    default: 0,
  },
  contactName: {
    type: String,
    default: '',
  },
  contactThumbnail: {
    type: String,
    default: '',
  },
  messageType: {
    type: Number,
    default: undefined,
  },
});

const { t } = useI18n();

const navigateTo = computed(() => {
  const params = {};
  if (props.messageId) {
    params.messageId = props.messageId;
  }
  return frontendURL(
    `accounts/${props.accountId}/conversations/${props.id}`,
    params
  );
});

const messageDateLabel = computed(() => {
  if (!props.createdAt) return '';
  const time = fromUnixTime(props.createdAt);
  if (isToday(time)) return messageStamp(props.createdAt, 'HH:mm');
  if (isYesterday(time)) {
    return `${t('SEARCH.YESTERDAY')}, ${messageStamp(props.createdAt, 'HH:mm')}`;
  }
  return dateFormat(props.createdAt, 'dd/MM/yyyy');
});

const isOutgoingMessage = computed(() => {
  return (
    props.messageType !== undefined &&
    props.messageType !== MESSAGE_TYPE.INCOMING
  );
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
          :name="contactName"
          :src="contactThumbnail"
          :size="28"
          rounded-full
          class="flex-shrink-0"
        />
        <div class="min-w-0 flex flex-col gap-2 flex-1">
          <div class="flex items-start justify-between gap-3 min-w-0 w-full">
            <h5
              class="m-0 text-sm font-medium truncate min-w-0 text-n-slate-12 flex-1"
            >
              {{ contactName }}
            </h5>
            <span
              v-if="messageDateLabel"
              class="text-xs leading-4 flex-shrink-0 text-n-slate-11 whitespace-nowrap"
            >
              {{ messageDateLabel }}
            </span>
          </div>
          <div class="flex items-center gap-1.5 min-w-0 w-full text-sm">
            <Icon
              v-if="isOutgoingMessage"
              icon="i-lucide-check-check"
              class="size-3.5 flex-shrink-0 text-n-slate-11"
            />
            <slot />
          </div>
        </div>
      </div>
    </CardLayout>
  </router-link>
</template>
