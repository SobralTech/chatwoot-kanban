<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import KanbanOpportunityMenu from './KanbanOpportunityMenu.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  cardDisplayId: {
    type: [Number, String],
    required: true,
  },
  openedFromConversation: {
    type: Boolean,
    default: false,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
  isPending: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'openConversation',
  'openConversationInNewTab',
  'openFunnel',
  'copyCardId',
  'copyCardLink',
  'removeCard',
  'close',
]);

const subject = defineModel('subject', {
  type: String,
  default: '',
});

const { t } = useI18n();
const titleInput = ref(null);
const draftSubject = ref('');
const isEditing = ref(false);
const localError = ref('');

const hasConversation = computed(() => !!props.card.conversationId);
const hasContact = computed(() => !!props.card.contact);
const inboxObject = computed(
  () => props.card.inbox || props.card.conversation?.inbox || null
);
const contact = computed(() => props.card.contact || {});
const contactName = computed(
  () =>
    contact.value.name ||
    contact.value.email ||
    contact.value.phoneNumber ||
    t('KANBAN.CARD.UNKNOWN_CONTACT')
);
const inboxName = computed(
  () => inboxObject.value?.name || t('KANBAN.CARD.UNKNOWN_INBOX')
);
// Only provenance lives here — who this deal is with and where it came in.
// Funnel position and stage age belong to the state row, and mixing all four
// entity types behind the same middot made none of them readable.
const subtitleItems = computed(() =>
  [
    { key: 'contact', label: contactName.value },
    hasConversation.value && !props.openedFromConversation
      ? { key: 'inbox', label: inboxName.value }
      : null,
  ].filter(Boolean)
);
const errorMessage = computed(() => localError.value);

const clearError = () => {
  localError.value = '';
};

const startEditing = () => {
  if (props.isPending) return;

  draftSubject.value = subject.value;
  localError.value = '';
  isEditing.value = true;
};

const focusTitleInput = () => {
  nextTick(() => titleInput.value?.focus?.());
};

const updateDraft = value => {
  draftSubject.value = value;
  clearError();
};

const commitEditing = () => {
  if (!draftSubject.value.trim()) {
    localError.value = t('KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE');
    focusTitleInput();
    return;
  }

  subject.value = draftSubject.value;
  clearError();
  isEditing.value = false;
};

const cancelEditing = () => {
  draftSubject.value = subject.value;
  clearError();
  isEditing.value = false;
};

const onTitleKeydown = event => {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    startEditing();
  }
};
</script>

<template>
  <div class="flex min-w-0 flex-1 items-start gap-2">
    <div class="min-w-0 flex-1">
      <div class="flex min-w-0 items-center gap-2">
        <div v-if="isEditing" class="min-w-0 flex-1">
          <div class="flex min-w-0 items-center gap-1">
            <InlineInput
              ref="titleInput"
              :model-value="draftSubject"
              focus-on-mount
              class="min-w-0 flex-1"
              data-testid="kanban-opportunity-title-input"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.EDIT_SUBJECT')"
              custom-input-class="font-semibold"
              :disabled="isPending"
              @update:model-value="updateDraft"
              @enter-press="commitEditing"
              @escape-press="cancelEditing"
              @blur="commitEditing"
            />
            <button
              type="button"
              data-testid="kanban-opportunity-title-confirm"
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-teal-11 disabled:cursor-not-allowed disabled:opacity-50"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CONFIRM_SUBJECT')"
              :title="t('KANBAN.OPPORTUNITY_DETAILS.CONFIRM_SUBJECT')"
              :disabled="isPending"
              @mousedown.prevent
              @click="commitEditing"
            >
              <i class="i-lucide-check size-4" />
            </button>
            <button
              type="button"
              data-testid="kanban-opportunity-title-cancel"
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-ruby-11 disabled:cursor-not-allowed disabled:opacity-50"
              :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL_SUBJECT')"
              :title="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL_SUBJECT')"
              :disabled="isPending"
              @mousedown.prevent
              @click="cancelEditing"
            >
              <i class="i-lucide-x size-4" />
            </button>
          </div>
          <p
            v-if="errorMessage"
            data-testid="kanban-opportunity-subject-error"
            class="mb-0 mt-1 text-xs text-n-ruby-11"
          >
            {{ errorMessage }}
          </p>
        </div>
        <h2
          v-else
          id="kanban-opportunity-title"
          data-testid="kanban-opportunity-title"
          class="-mx-1 mb-0 min-w-0 flex-1 truncate rounded-md px-1 text-lg font-semibold leading-7 text-n-slate-12 hover:bg-n-alpha-1"
          role="button"
          tabindex="0"
          :title="subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE')"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.EDIT_SUBJECT')"
          :aria-disabled="isPending"
          :class="{ 'cursor-not-allowed opacity-60': isPending }"
          @click="startEditing"
          @keydown="onTitleKeydown"
        >
          {{ subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE') }}
        </h2>
        <!-- Nothing waits for a save button any more, so the only state left to
        report is that a change is on its way to the server. -->
        <span
          v-if="isSaving"
          data-testid="kanban-opportunity-saving-indicator"
          class="inline-flex flex-shrink-0 items-center gap-1.5 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
        >
          <i class="i-lucide-loader-circle size-3 animate-spin" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.SAVING_STATE') }}
        </span>
      </div>

      <div
        data-testid="kanban-opportunity-subtitle"
        class="mt-1.5 flex min-w-0 items-center overflow-hidden text-sm leading-5 text-n-slate-11"
      >
        <template v-for="(item, index) in subtitleItems" :key="item.key">
          <span v-if="index" class="mx-1 flex-shrink-0">·</span>
          <span
            class="flex min-w-0 max-w-[14rem] flex-shrink items-center gap-1.5 truncate"
            :title="item.label"
          >
            <Avatar
              v-if="item.key === 'contact' && hasContact"
              :name="item.label"
              :src="contact.thumbnail"
              :size="20"
              rounded-full
            />
            <i
              v-else-if="item.key === 'contact'"
              class="i-lucide-user-round size-4 flex-shrink-0"
            />
            <ChannelIcon
              v-else-if="item.key === 'inbox' && inboxObject"
              :inbox="inboxObject"
              class="size-4 flex-shrink-0"
            />
            <i
              v-else-if="item.key === 'inbox'"
              class="i-lucide-inbox size-4 flex-shrink-0"
            />
            <span class="min-w-0 truncate">{{ item.label }}</span>
          </span>
        </template>
      </div>
    </div>

    <div class="flex flex-shrink-0 items-center gap-1">
      <KanbanOpportunityMenu
        :card="card"
        :card-display-id="cardDisplayId"
        :opened-from-conversation="openedFromConversation"
        @open-conversation="emit('openConversation', $event)"
        @open-conversation-in-new-tab="emit('openConversationInNewTab', $event)"
        @open-funnel="emit('openFunnel', $event)"
        @copy-card-id="emit('copyCardId')"
        @copy-card-link="emit('copyCardLink', $event)"
        @remove-card="emit('removeCard', $event)"
      />
      <button
        type="button"
        data-testid="kanban-opportunity-close"
        class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
        :title="t('KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL')"
        @click="emit('close')"
      >
        <i class="i-lucide-x size-4" />
      </button>
    </div>
  </div>
</template>
