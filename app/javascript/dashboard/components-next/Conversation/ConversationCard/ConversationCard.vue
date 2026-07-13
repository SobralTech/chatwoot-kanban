<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { useRouter, useRoute } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper.js';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import wootConstants from 'dashboard/constants/globals';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import CardMessagePreview from './CardMessagePreview.vue';
import CardMessagePreviewWithMeta from './CardMessagePreviewWithMeta.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  contact: {
    type: Object,
    required: true,
  },
  stateInbox: {
    type: Object,
    required: true,
  },
  accountLabels: {
    type: Array,
    required: true,
  },
  showInboxAsHeader: {
    type: Boolean,
    default: false,
  },
  hideAssignee: {
    type: Boolean,
    default: false,
  },
});

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const cardMessagePreviewWithMetaRef = ref(null);

const currentContact = computed(() => props.contact);

const currentContactName = computed(() => currentContact.value?.name);
const currentContactThumbnail = computed(() => currentContact.value?.thumbnail);
const currentContactStatus = computed(
  () => currentContact.value?.availabilityStatus
);

const isArchived = computed(() => !!props.conversation.archivedAt);

const inbox = computed(() => props.stateInbox);

const inboxName = computed(() => inbox.value?.name);

const inboxIcon = computed(() => {
  const { channelType, medium, name } = inbox.value;
  return getInboxIconByType(channelType, medium, 'fill', name);
});

const lastActivityAt = computed(() => {
  const timestamp = props.conversation?.timestamp;
  return timestamp ? shortTimestamp(dynamicTime(timestamp)) : '';
});

const showMessagePreviewWithoutMeta = computed(() => {
  const { labels = [] } = props.conversation;
  return (
    !cardMessagePreviewWithMetaRef.value?.hasSlaThreshold && labels.length === 0
  );
});

const onCardClick = e => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.conversation.id,
      conversationType: isArchived.value
        ? wootConstants.CONVERSATION_TYPE.ARCHIVED
        : '',
    })
  );

  if (e.metaKey || e.ctrlKey) {
    window.open(
      window.chatwootConfig.hostURL + path,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }
  router.push({ path });
};
</script>

<template>
  <div
    role="button"
    class="flex w-full gap-3 px-3 py-4 transition-all duration-300 ease-in-out cursor-pointer"
    @click="onCardClick"
  >
    <Avatar
      v-if="!showInboxAsHeader"
      :name="currentContactName"
      :src="currentContactThumbnail"
      :size="24"
      :status="currentContactStatus"
      rounded-full
    />
    <div
      v-else
      class="flex items-center justify-center flex-shrink-0 rounded-full bg-n-alpha-2 size-6"
    >
      <Icon :icon="inboxIcon" class="flex-shrink-0 text-n-slate-11 size-3" />
    </div>
    <div class="flex flex-col w-full gap-1 min-w-0">
      <div class="flex items-center justify-between h-6 gap-2">
        <h4 class="text-base font-medium truncate text-n-slate-12">
          {{ showInboxAsHeader ? inboxName : currentContactName }}
        </h4>
        <div class="flex items-center gap-2">
          <CardPriorityIcon :priority="conversation.priority || null" />
          <Icon
            v-if="isArchived"
            v-tooltip.top="{
              content: t(
                'CONVERSATION.CARD_CONTEXT_MENU.CONVERSATION_ARCHIVED'
              ),
              delay: { show: 500, hide: 0 },
            }"
            icon="i-lucide-archive"
            class="flex-shrink-0 text-n-slate-9 size-4"
          />
          <div
            v-if="!showInboxAsHeader"
            v-tooltip.left="inboxName"
            class="flex items-center justify-center flex-shrink-0 rounded-full bg-n-alpha-2 size-5"
          >
            <Icon
              :icon="inboxIcon"
              class="flex-shrink-0 text-n-slate-11 size-3"
            />
          </div>
          <span class="text-sm text-n-slate-10">
            {{ lastActivityAt }}
          </span>
        </div>
      </div>
      <CardMessagePreview
        v-show="showMessagePreviewWithoutMeta"
        :conversation="conversation"
        :hide-assignee="hideAssignee"
      />
      <CardMessagePreviewWithMeta
        v-show="!showMessagePreviewWithoutMeta"
        ref="cardMessagePreviewWithMetaRef"
        :conversation="conversation"
        :account-labels="accountLabels"
        :hide-assignee="hideAssignee"
      />
    </div>
  </div>
</template>
