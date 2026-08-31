<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import KanbanDueDateBadge from '../KanbanDueDateBadge.vue';
import {
  formatCompactCurrency,
  formatCurrency,
} from 'dashboard/helper/kanbanCurrency';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['openDetails']);

const { t } = useI18n();

const contact = computed(() => props.card.contact || {});
const contactName = computed(
  () => contact.value.name || t('KANBAN.CARD.UNKNOWN_CONTACT')
);
const contactThumbnail = computed(
  () => contact.value.thumbnail || contact.value.avatarUrl || ''
);
const subject = computed(() => props.card.subject || contactName.value);
const inbox = computed(() => props.card.inbox || {});
const inboxName = computed(
  () => inbox.value.name || t('KANBAN.CARD.UNKNOWN_INBOX')
);
const namedInbox = computed(() => ({ ...inbox.value, name: inboxName.value }));
const priority = computed(() => props.card.cardPriority || '');
const dueAt = computed(() => props.card.dueAt);
const assignees = computed(() => props.card.assignees || []);
const visibleAssignees = computed(() => assignees.value.slice(0, 3));
const extraAssigneeCount = computed(() =>
  Math.max(assignees.value.length - visibleAssignees.value.length, 0)
);
const cardValue = computed(() => Number(props.card.value) || 0);
</script>

<template>
  <article
    tabindex="0"
    class="flex w-full min-w-0 cursor-pointer flex-wrap items-center gap-x-3 gap-y-1 rounded-lg px-2 py-2 text-left hover:bg-n-alpha-1"
    :data-card-id="card.id"
    @click="emit('openDetails', card)"
  >
    <span class="flex flex-shrink-0 rounded-full" :title="contactName">
      <Avatar
        :name="contactName"
        :src="contactThumbnail"
        :size="28"
        rounded-full
      />
    </span>

    <span class="min-w-32 flex-1">
      <span
        class="block truncate text-sm font-medium leading-4 text-n-slate-12"
        :title="subject"
      >
        {{ subject }}
      </span>
      <span
        class="mt-1 flex min-w-0 items-center gap-1 text-xs leading-4 text-n-slate-11"
      >
        <span class="max-w-40 truncate" :title="contactName">
          {{ contactName }}
        </span>
        <ChannelIcon
          :inbox="namedInbox"
          class="size-3.5 flex-shrink-0 text-n-slate-11"
        />
        <InboxName :inbox="namedInbox" :show-icon="false" class="min-w-0" />
      </span>
    </span>

    <span class="flex flex-shrink-0 items-center gap-2 text-xs ms-auto">
      <CardPriorityIcon :priority="priority" show-empty class="!size-3.5" />

      <KanbanDueDateBadge v-if="dueAt" :due-at="dueAt" />

      <span
        v-if="visibleAssignees.length"
        class="-space-x-1 flex flex-shrink-0 items-center"
      >
        <span
          v-for="assignee in visibleAssignees"
          :key="assignee.id"
          data-testid="kanban-list-row-assignee"
          class="flex flex-shrink-0 rounded-full ring-2 ring-n-solid-2"
          :title="assignee.name"
        >
          <Avatar
            :name="assignee.name"
            :src="assignee.avatarUrl"
            :size="20"
            rounded-full
          />
        </span>
        <span
          v-if="extraAssigneeCount"
          data-testid="kanban-list-row-assignee-overflow"
          class="flex size-5 flex-shrink-0 items-center justify-center rounded-full bg-n-slate-3 text-[9px] font-medium leading-none text-n-slate-11 ring-2 ring-n-solid-2"
        >
          {{ `+${extraAssigneeCount}` }}
        </span>
      </span>

      <span
        v-if="cardValue > 0"
        data-testid="kanban-list-row-value"
        class="flex-shrink-0 font-medium text-n-slate-11"
        :title="formatCurrency(cardValue)"
      >
        {{ formatCompactCurrency(cardValue) }}
      </span>
    </span>
  </article>
</template>
