<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['openDetails', 'openConversation', 'removeCard']);

defineOptions({
  inheritAttrs: false,
});

const { t } = useI18n();
const store = useStore();
const pointerStart = ref(null);
const hasPointerMoved = ref(false);
const dragClickThreshold = 5;

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
const subject = computed(() => props.card.subject || contactName.value);
const contactAvatar = computed(
  () =>
    contact.value?.thumbnail ||
    contact.value?.avatarUrl ||
    contact.value?.avatar_url ||
    ''
);
const priority = computed(
  () => props.card.priority || conversation.value.priority || ''
);
const hasSupportedPriority = computed(() =>
  Object.values(CONVERSATION_PRIORITY).includes(priority.value)
);
const assignee = computed(
  () => props.card.assignee || conversation.value?.meta?.assignee || null
);
const hasAssignee = computed(() => !!assignee.value?.name);
const assigneeAvatar = computed(
  () => assignee.value?.avatarUrl || assignee.value?.avatar_url || ''
);
const normalizedInbox = computed(() => ({
  ...(inbox.value || {}),
  name:
    inbox.value?.name ||
    conversation.value?.meta?.channel ||
    t('KANBAN.CARD.UNKNOWN_INBOX'),
}));
const stageEnteredAt = computed(
  () => props.card.stageEnteredAt || props.card.stage_entered_at
);
const stageDuration = computed(() => {
  if (!stageEnteredAt.value) return '';

  const enteredAt = new Date(stageEnteredAt.value).getTime();
  if (Number.isNaN(enteredAt)) return '';

  const elapsedMinutes = Math.max(
    Math.floor((Date.now() - enteredAt) / 60000),
    0
  );
  if (elapsedMinutes < 60) return `${elapsedMinutes || 1}m`;

  const elapsedHours = Math.floor(elapsedMinutes / 60);
  if (elapsedHours < 24) return `${elapsedHours}h`;

  return `${Math.floor(elapsedHours / 24)}d`;
});
const dueAt = computed(() => props.card.dueAt || props.card.due_at);
const dueDate = computed(() => {
  if (!dueAt.value) return '';

  const date = new Date(dueAt.value);
  if (Number.isNaN(date.getTime())) return '';

  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
  }).format(date);
});
const dueDateTitle = computed(() => {
  if (!dueAt.value) return '';

  const date = new Date(dueAt.value);
  if (Number.isNaN(date.getTime())) return '';

  return date.toLocaleString();
});
const cardTitle = computed(() =>
  hasConversation.value
    ? t('KANBAN.CARD.CONVERSATION_ID', { id: props.card.conversationId })
    : t('KANBAN.CARD.NO_LINKED_CONVERSATION')
);

const openDetails = event => {
  emit('openDetails', props.card, event);
};

const removeCard = event => {
  emit('removeCard', props.card, event);
};

const onCardPointerDown = event => {
  pointerStart.value = {
    x: event.clientX,
    y: event.clientY,
  };
  hasPointerMoved.value = false;
};

const onCardPointerMove = event => {
  if (!pointerStart.value || hasPointerMoved.value) return;

  const deltaX = Math.abs(event.clientX - pointerStart.value.x);
  const deltaY = Math.abs(event.clientY - pointerStart.value.y);
  hasPointerMoved.value =
    deltaX > dragClickThreshold || deltaY > dragClickThreshold;
};

const openConversation = event => {
  if (hasPointerMoved.value) {
    hasPointerMoved.value = false;
    pointerStart.value = null;
    return;
  }

  pointerStart.value = null;

  if (!hasConversation.value) return;

  emit('openConversation', props.card, event);
};
</script>

<template>
  <article
    class="card-drag-handle group relative cursor-grab rounded-lg border border-n-weak bg-n-surface-1 p-2"
    :data-card-id="card.id"
    :data-conversation-id="card.conversationId"
    :title="cardTitle"
    @pointerdown="onCardPointerDown"
    @pointermove="onCardPointerMove"
    @click="openConversation"
  >
    <div
      class="pointer-events-none absolute right-1.5 top-1.5 z-10 flex gap-1 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100"
      data-testid="kanban-card-hover-actions"
    >
      <button
        type="button"
        data-testid="kanban-card-edit"
        class="no-drag pointer-events-auto flex size-7 items-center justify-center rounded-md bg-n-surface-1 text-n-slate-11 shadow-sm ring-1 ring-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="t('KANBAN.CARD.EDIT')"
        :aria-label="t('KANBAN.CARD.EDIT')"
        @click.stop="openDetails"
      >
        <i class="i-lucide-pencil size-4" />
      </button>
      <button
        type="button"
        data-testid="kanban-card-delete"
        class="no-drag pointer-events-auto flex size-7 items-center justify-center rounded-md bg-n-surface-1 text-n-slate-11 shadow-sm ring-1 ring-n-weak hover:bg-n-alpha-2 hover:text-n-ruby-11"
        :title="t('KANBAN.CARD.DELETE')"
        :aria-label="t('KANBAN.CARD.DELETE')"
        @click.stop="removeCard"
      >
        <i class="i-lucide-trash-2 size-4" />
      </button>
    </div>
    <div class="space-y-1 text-left">
      <h4
        class="truncate text-sm font-medium leading-5 text-n-slate-12"
        :title="subject"
      >
        {{ subject }}
      </h4>

      <div class="flex min-w-0 items-center gap-1.5">
        <button
          v-if="hasConversation"
          type="button"
          data-testid="contact-avatar"
          class="relative flex size-7 flex-shrink-0 cursor-pointer items-center justify-center rounded-full"
          :title="contactName"
          :aria-label="contactName"
          @click.stop="openConversation"
        >
          <Avatar
            :name="contactName"
            :src="contactAvatar"
            :size="28"
            rounded-full
          />
          <span
            data-testid="inbox-avatar-badge"
            class="absolute -bottom-0.5 -right-0.5 flex size-3.5 items-center justify-center rounded-full bg-n-surface-1 ring-1 ring-n-weak"
            :title="normalizedInbox.name"
          >
            <ChannelIcon :inbox="normalizedInbox" class="size-2.5" />
          </span>
        </button>
        <div
          v-else
          data-testid="contact-avatar"
          class="relative flex size-7 flex-shrink-0 cursor-default items-center justify-center rounded-full"
          :title="contactName"
          @click.stop
        >
          <Avatar
            :name="contactName"
            :src="contactAvatar"
            :size="28"
            rounded-full
          />
          <span
            data-testid="inbox-avatar-badge"
            class="absolute -bottom-0.5 -right-0.5 flex size-3.5 items-center justify-center rounded-full bg-n-surface-1 ring-1 ring-n-weak"
            :title="normalizedInbox.name"
          >
            <ChannelIcon :inbox="normalizedInbox" class="size-2.5" />
          </span>
        </div>
        <span
          class="min-w-0 flex-1 truncate text-xs leading-4 text-n-slate-11"
          :title="contactName"
        >
          {{ contactName }}
        </span>
        <Avatar
          v-if="hasAssignee"
          :name="assignee.name"
          :src="assigneeAvatar"
          :size="18"
          rounded-full
          :title="assignee.name"
        />
      </div>

      <div
        data-testid="inbox-pill"
        class="inline-flex max-w-full items-center rounded-md bg-n-alpha-2 px-1.5 py-0.5"
        :title="normalizedInbox.name"
      >
        <span class="truncate text-label-small text-n-slate-11">
          {{ normalizedInbox.name }}
        </span>
      </div>

      <div class="flex min-w-0 items-center gap-2 text-xs text-n-slate-10">
        <CardPriorityIcon
          v-if="hasSupportedPriority"
          data-testid="priority-indicator"
          :priority="priority"
        />
        <span class="flex-1" />
        <span
          v-if="stageDuration"
          class="flex-shrink-0 tabular-nums"
          :title="stageEnteredAt"
        >
          {{ stageDuration }}
        </span>
        <span
          v-if="dueDate"
          class="flex min-w-0 flex-shrink-0 items-center gap-1 truncate"
          :title="dueDateTitle"
        >
          <i class="i-lucide-calendar size-3" />
          {{ dueDate }}
        </span>
      </div>
    </div>
  </article>
</template>
