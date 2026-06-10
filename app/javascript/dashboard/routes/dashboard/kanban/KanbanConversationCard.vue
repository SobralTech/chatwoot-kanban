<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

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

const emit = defineEmits(['openDetails', 'removeCard']);

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
const displayId = computed(() =>
  t('KANBAN.CARD.CONVERSATION_ID', { id: props.card.conversationId })
);
const status = computed(
  () => conversation.value.status || t('KANBAN.CARD.UNKNOWN_STATUS')
);
const priority = computed(() => conversation.value.priority || '');
const hasSupportedPriority = computed(() =>
  Object.values(CONVERSATION_PRIORITY).includes(priority.value)
);
const assigneeName = computed(
  () => conversation.value?.meta?.assignee?.name || t('KANBAN.CARD.UNASSIGNED')
);
const inboxName = computed(
  () =>
    inbox.value?.name ||
    conversation.value?.meta?.channel ||
    t('KANBAN.CARD.UNKNOWN_INBOX')
);
const lastActivityAt = computed(() => conversation.value.lastActivityAt);
const lastActivity = computed(() =>
  lastActivityAt.value
    ? dynamicTime(lastActivityAt.value)
    : t('KANBAN.CARD.UNKNOWN_LAST_ACTIVITY')
);
const lastMessage = computed(
  () =>
    (!hasConversation.value && t('KANBAN.CARD.NO_LINKED_CONVERSATION')) ||
    conversation.value?.messages?.[0]?.content ||
    conversation.value?.lastNonActivityMessage?.content ||
    t('KANBAN.CARD.NO_MESSAGES')
);

const openDetails = event => {
  emit('openDetails', props.card, event);
};
</script>

<template>
  <article
    class="card-drag-handle cursor-grab rounded-lg border border-n-weak bg-n-surface-1 p-3"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    @click="openDetails"
  >
    <div class="text-left">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <p
            v-if="card.subject"
            class="truncate text-sm font-medium text-n-slate-12"
          >
            {{ card.subject }}
          </p>
          <h4
            class="min-w-0 truncate text-sm text-n-slate-12"
            :class="{ 'font-medium': !card.subject }"
          >
            {{ contactName }}
          </h4>
        </div>
        <div class="flex items-center gap-2">
          <span
            v-if="hasConversation"
            class="flex-shrink-0 text-xs text-n-slate-10"
          >
            {{ displayId }}
          </span>
        </div>
      </div>

      <p class="mt-2 line-clamp-2 text-sm leading-5 text-n-slate-11">
        {{ lastMessage }}
      </p>
    </div>

    <div class="mt-3 grid gap-2 text-xs text-n-slate-11">
      <div class="flex items-center justify-between gap-2">
        <span class="min-w-0 truncate">
          {{ t('KANBAN.CARD.INBOX', { inbox: inboxName }) }}
        </span>
        <span class="flex-shrink-0 rounded-md bg-n-alpha-2 px-2 py-1">
          {{ status }}
        </span>
      </div>
      <div class="flex items-center justify-between gap-2">
        <span class="min-w-0 truncate">
          {{ t('KANBAN.CARD.ASSIGNEE', { assignee: assigneeName }) }}
        </span>
        <CardPriorityIcon
          v-if="hasSupportedPriority"
          :priority="priority"
          class="flex-shrink-0"
        />
      </div>
      <span class="truncate text-n-slate-10">
        {{ t('KANBAN.CARD.LAST_ACTIVITY', { time: lastActivity }) }}
      </span>
    </div>

    <div class="mt-3 flex items-center justify-end">
      <button
        type="button"
        class="no-drag flex items-center gap-1 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-ruby-11 hover:bg-n-ruby-2 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!!activeActionKey"
        @click.stop="emit('removeCard', card)"
      >
        <i class="i-lucide-trash size-4" />
        {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
      </button>
    </div>
  </article>
</template>
