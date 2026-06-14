<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { format } from 'date-fns';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import InboxName from 'dashboard/components/widgets/InboxName.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  activeActionKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['openDetails', 'openConversation', 'removeCard']);

const { t } = useI18n();
const store = useStore();

const conversation = computed(() => props.card.conversation || {});
const contact = computed(
  () => props.card.contact || conversation.value?.meta?.sender || {}
);
const inbox = computed(
  () =>
    props.card.inbox ||
    store.getters['inboxes/getInboxById'](conversation.value.inboxId)
);

const hasConversation = computed(() => !!props.card.conversationId);
const contactName = computed(
  () => contact.value?.name || t('KANBAN.CARD.UNKNOWN_CONTACT')
);
const priority = computed(() => conversation.value.priority || '');
const hasSupportedPriority = computed(() =>
  Object.values(CONVERSATION_PRIORITY).includes(priority.value)
);
const inboxName = computed(
  () =>
    inbox.value?.name ||
    conversation.value?.meta?.channel ||
    t('KANBAN.CARD.UNKNOWN_INBOX')
);
const contactThumbnail = computed(
  () => contact.value?.thumbnail || contact.value?.avatarUrl || ''
);
const assignee = computed(() => conversation.value?.meta?.assignee || null);
const assigneeName = computed(() => assignee.value?.name || '');
const assigneeThumbnail = computed(
  () => assignee.value?.thumbnail || assignee.value?.avatarUrl || ''
);
const subject = computed(() => props.card.subject || '');

const toUnixTimestamp = value => {
  if (!value) return null;
  if (typeof value === 'number') return value;

  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? null : Math.floor(timestamp / 1000);
};

const stageEnteredAt = computed(() =>
  toUnixTimestamp(props.card.stage_entered_at || props.card.stageEnteredAt)
);
const stageTime = computed(() =>
  stageEnteredAt.value
    ? shortTimestamp(dynamicTime(stageEnteredAt.value), true)
    : ''
);
const dueAt = computed(() => props.card.due_at || props.card.dueAt);
const dueAtLabel = computed(() => {
  if (!dueAt.value) return '';

  const dueDate = new Date(dueAt.value);
  return Number.isNaN(dueDate.getTime()) ? '' : format(dueDate, 'MMM d');
});

const openDetails = event => {
  emit('openDetails', props.card, event);
};

const openConversation = event => {
  if (!hasConversation.value) return;

  emit('openConversation', props.card, event);
};
</script>

<template>
  <article
    class="card-drag-handle group relative cursor-grab rounded-lg border border-n-weak bg-n-surface-1 p-2"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    @click="openDetails"
  >
    <button
      type="button"
      data-testid="kanban-card-remove"
      class="no-drag pointer-events-auto absolute top-1.5 ltr:right-1.5 rtl:left-1.5 flex size-8 items-center justify-center rounded-md border border-n-weak bg-n-surface-1 text-n-ruby-11 opacity-0 shadow-sm transition-opacity hover:bg-n-ruby-2 focus:opacity-100 focus:outline-none focus:ring-1 focus:ring-n-ruby-8 group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-50"
      :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
      :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
      :disabled="!!activeActionKey"
      @click.stop="emit('removeCard', card)"
    >
      <i class="i-lucide-trash size-5" />
    </button>

    <div class="min-w-0 text-left">
      <p
        v-if="subject"
        class="truncate text-sm font-medium leading-4 text-n-slate-12"
        :title="subject"
      >
        {{ subject }}
      </p>

      <div class="mt-1 flex items-center gap-1.5">
        <button
          type="button"
          data-testid="kanban-card-contact-avatar"
          class="no-drag relative flex flex-shrink-0 rounded-full focus:outline-none focus:ring-1 focus:ring-n-brand"
          :title="contactName"
          @click.stop="openConversation"
        >
          <Avatar
            :name="contactName"
            :src="contactThumbnail"
            :size="28"
            rounded-full
          />
          <span
            v-if="inbox"
            class="absolute -bottom-1 -right-1 flex size-5 items-center justify-center rounded-full border border-n-surface-1 bg-n-surface-1"
          >
            <ChannelIcon :inbox="inbox" class="size-3.5 text-n-slate-11" />
          </span>
        </button>

        <h4
          class="min-w-0 flex-1 truncate text-xs font-medium leading-4 text-n-slate-12"
        >
          {{ contactName }}
        </h4>

        <Avatar
          v-if="assigneeName"
          :name="assigneeName"
          :src="assigneeThumbnail"
          :size="18"
          rounded-full
        />
      </div>

      <div class="mt-1 flex min-w-0">
        <div
          class="inline-flex max-w-full items-center rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xs leading-4"
        >
          <InboxName
            :inbox="{ ...inbox, name: inboxName }"
            :show-icon="false"
            class="max-w-full"
          />
        </div>
      </div>

      <div
        v-if="hasSupportedPriority || stageTime || dueAtLabel"
        data-testid="kanban-card-meta"
        class="mt-1 flex items-center justify-between gap-1.5 text-xs leading-4 text-n-slate-10"
      >
        <CardPriorityIcon
          v-if="hasSupportedPriority"
          :priority="priority"
          class="flex-shrink-0 !size-3.5"
        />
        <span v-else />

        <div class="flex min-w-0 items-center justify-end gap-1.5">
          <span
            v-if="stageTime"
            class="truncate"
            :title="dynamicTime(stageEnteredAt)"
          >
            {{ stageTime }}
          </span>
          <span v-if="dueAtLabel" class="flex-shrink-0" :title="dueAt">
            {{ dueAtLabel }}
          </span>
        </div>
      </div>
    </div>
  </article>
</template>
