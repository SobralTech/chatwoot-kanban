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
  boardName: {
    type: String,
    default: '',
  },
  hasUnsavedChanges: {
    type: Boolean,
    default: false,
  },
  subjectError: {
    type: String,
    default: '',
  },
});

const emit = defineEmits([
  'clearSubjectError',
  'subjectError',
  'openConversation',
  'copyCardId',
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
    t('KANBAN.OPPORTUNITY_DETAILS.NO_CONTACT')
);
const inboxName = computed(
  () => inboxObject.value?.name || t('KANBAN.OPPORTUNITY_DETAILS.NO_INBOX')
);
const subtitleItems = computed(() =>
  [
    { key: 'contact', label: contactName.value },
    hasConversation.value ? { key: 'inbox', label: inboxName.value } : null,
    props.boardName ? { key: 'board', label: props.boardName } : null,
  ].filter(Boolean)
);
const errorMessage = computed(() => props.subjectError || localError.value);

const clearError = () => {
  localError.value = '';
  emit('clearSubjectError');
};

const startEditing = () => {
  draftSubject.value = subject.value;
  localError.value = '';
  emit('clearSubjectError');
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
    emit('subjectError', localError.value);
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
          <InlineInput
            ref="titleInput"
            :model-value="draftSubject"
            focus-on-mount
            data-testid="kanban-opportunity-title-input"
            :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.EDIT_SUBJECT')"
            custom-input-class="font-semibold"
            @update:model-value="updateDraft"
            @enter-press="commitEditing"
            @escape-press="cancelEditing"
            @blur="commitEditing"
          />
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
          class="mb-0 min-w-0 flex-1 truncate text-base font-semibold text-n-slate-12"
          role="button"
          tabindex="0"
          :title="subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE')"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.EDIT_SUBJECT')"
          @click="startEditing"
          @keydown="onTitleKeydown"
        >
          {{ subject || t('KANBAN.OPPORTUNITY_DETAILS.TITLE') }}
        </h2>
        <span
          v-if="hasUnsavedChanges"
          data-testid="kanban-opportunity-unsaved-indicator"
          class="inline-flex flex-shrink-0 items-center gap-1.5 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
        >
          <span class="size-1.5 rounded-full bg-n-amber-9" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_INDICATOR') }}
        </span>
      </div>

      <div
        data-testid="kanban-opportunity-subtitle"
        class="mt-1 flex min-w-0 items-center overflow-hidden text-xs text-n-slate-11"
      >
        <template v-for="(item, index) in subtitleItems" :key="item.key">
          <span v-if="index" class="mx-1 flex-shrink-0">·</span>
          <span
            class="flex min-w-0 max-w-[12rem] flex-shrink items-center gap-1 truncate"
            :title="item.label"
          >
            <Avatar
              v-if="item.key === 'contact' && hasContact"
              :name="item.label"
              :src="contact.thumbnail"
              :size="16"
              rounded-full
            />
            <i
              v-else-if="item.key === 'contact'"
              class="i-lucide-user-round size-3.5 flex-shrink-0"
            />
            <ChannelIcon
              v-else-if="item.key === 'inbox' && inboxObject"
              :inbox="inboxObject"
              class="size-3.5 flex-shrink-0"
            />
            <i
              v-else-if="item.key === 'inbox'"
              class="i-lucide-inbox size-3.5 flex-shrink-0"
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
        @open-conversation="emit('openConversation', $event)"
        @copy-card-id="emit('copyCardId')"
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
