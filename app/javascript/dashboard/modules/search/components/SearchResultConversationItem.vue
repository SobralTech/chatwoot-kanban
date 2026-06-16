<script setup>
import { computed } from 'vue';
import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { humanTimestamp } from 'shared/helpers/timeHelper';
import { useInbox } from 'dashboard/composables/useInbox';
import { getInboxIconByType } from 'dashboard/helper/inbox';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  id: {
    type: Number,
    default: 0,
  },
  inbox: {
    type: Object,
    default: () => ({}),
  },
  name: {
    type: String,
    default: '',
  },
  email: {
    type: String,
    default: '',
  },
  phone: {
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
  messageId: {
    type: Number,
    default: 0,
  },
  emailSubject: {
    type: String,
    default: '',
  },
});

const { inbox } = useInbox(props.inbox?.id);

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

const lastActivityAtTime = computed(() => {
  if (!props.lastActivityAt) return '';
  return humanTimestamp(props.lastActivityAt);
});

const infoItems = computed(() => [
  {
    value: props.email,
    show: !!props.email,
  },
  {
    value: props.phone,
    show: !!props.phone,
  },
  {
    value: props.emailSubject,
    show: !!props.emailSubject,
  },
]);

const visibleInfoItems = computed(() =>
  infoItems.value.filter(item => item.show)
);

const inboxName = computed(() => props.inbox?.name);

const inboxDetails = computed(() => inbox.value || props.inbox || {});

const inboxIcon = computed(() => {
  const { channelType, medium, name } = inboxDetails.value;
  if (!channelType) return null;
  return getInboxIconByType(channelType, medium, 'fill', name);
});
</script>

<template>
  <router-link :to="navigateTo">
    <CardLayout
      layout="row"
      class="[&>div]:justify-start [&>div]:gap-3 [&>div]:px-4 [&>div]:py-3 [&>div]:items-start hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <Avatar
        :name="name"
        :src="thumbnail"
        :size="32"
        rounded-full
        class="mt-0.5 flex-shrink-0"
      />
      <div class="min-w-0 flex flex-col items-start gap-1.5 w-full">
        <div class="flex items-center min-w-0 gap-3 w-full h-7">
          <h5 class="m-0 text-sm font-medium truncate min-w-0 text-n-slate-12">
            {{ name }}
          </h5>
          <div v-if="inboxName" class="w-px h-3 bg-n-strong" />
          <div v-if="inboxName" class="flex items-center gap-1.5 min-w-0">
            <div
              v-if="inboxIcon"
              class="flex items-center justify-center flex-shrink-0 rounded-full bg-n-alpha-2 size-4"
            >
              <Icon
                :icon="inboxIcon"
                class="flex-shrink-0 text-n-slate-11 size-2.5"
              />
            </div>
            <span class="text-sm leading-4 text-n-slate-12 truncate min-w-0">
              {{ inboxName }}
            </span>
          </div>
        </div>
        <div class="flex items-start justify-between gap-3 w-full min-w-0">
          <div class="flex flex-wrap gap-x-2 gap-y-1.5 items-center min-w-0">
            <template
              v-for="(item, index) in visibleInfoItems"
              :key="`info-${index}`"
            >
              <span class="text-sm leading-4 min-w-0 text-n-slate-11 truncate">
                {{ item.value }}
              </span>
              <div
                v-if="index < visibleInfoItems.length - 1"
                class="w-px h-3 bg-n-strong"
              />
            </template>
          </div>
          <span
            v-if="lastActivityAtTime"
            class="text-sm leading-4 flex-shrink-0 text-right text-n-slate-11 whitespace-nowrap"
          >
            {{ $t('SEARCH.LAST_MESSAGE', { time: lastActivityAtTime }) }}
          </span>
        </div>
        <slot />
      </div>
    </CardLayout>
  </router-link>
</template>
