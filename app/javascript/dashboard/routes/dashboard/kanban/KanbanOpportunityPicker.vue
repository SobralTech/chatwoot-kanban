<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { debounce } from '@chatwoot/utils';
import { useStore } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  dateFormat,
  dynamicTime,
  shortTimestamp,
} from 'shared/helpers/timeHelper';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants';

const props = defineProps({
  kanbanBoardId: {
    type: Number,
    required: true,
  },
  kanbanStageId: {
    type: Number,
    required: true,
  },
  kanbanStageName: {
    type: String,
    default: '',
  },
  inboxScopeMode: {
    type: String,
    default: 'all_inboxes',
  },
  allowedInboxIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['created', 'close']);

const { t } = useI18n();
const store = useStore();

const CONTACT_SEARCH_MINIMUM_LENGTH = 2;
const CONVERSATIONS_PAGE_SIZE = 20;

const ATTACHMENT_PREVIEW_ICONS = {
  [ATTACHMENT_TYPES.IMAGE]: 'i-lucide-image',
  [ATTACHMENT_TYPES.AUDIO]: 'i-lucide-audio-lines',
  [ATTACHMENT_TYPES.VIDEO]: 'i-lucide-video',
  [ATTACHMENT_TYPES.FILE]: 'i-lucide-paperclip',
};

const contactSearchQuery = ref('');
const recentContacts = ref([]);
const searchResults = ref([]);
const selectedContact = ref(null);
const isSearchingContacts = ref(false);
const isLoadingRecentContacts = ref(false);
const contactSearchError = ref(false);
const contactSearchController = ref(null);

const conversations = ref([]);
const hasMoreRecentConversations = ref(false);
const contactableInboxes = ref([]);
const selectedConversation = ref(null);
const selectedFallbackInbox = ref(null);
const activeCards = ref([]);
const isLoadingContactDetails = ref(false);
const contactDetailsError = ref(false);
const contactDetailsController = ref(null);

const subject = ref('');
const subjectError = ref('');
const creationError = ref('');
const isSaving = ref(false);
const contactSearchInputRef = ref(null);
const subjectInputRef = ref(null);

const trimmedSubject = computed(() => subject.value.trim());
const hasUnsavedChanges = computed(() => trimmedSubject.value.length > 0);
const isLoadingContacts = computed(
  () => isLoadingRecentContacts.value || isSearchingContacts.value
);
const isSearchActive = computed(
  () => contactSearchQuery.value.trim().length >= CONTACT_SEARCH_MINIMUM_LENGTH
);
const selectedInbox = computed(
  () => selectedConversation.value?.inbox || selectedFallbackInbox.value
);
const currentStep = computed(() => {
  if (!selectedContact.value) return 1;

  return selectedInbox.value ? 3 : 2;
});

const pickerTitle = computed(() => {
  const title = t('KANBAN.ADD_ITEM.TITLE_WITH_STAGE', {
    stageName: props.kanbanStageName,
  });

  return title.replace(`«${props.kanbanStageName}»`, props.kanbanStageName);
});
const activeCardConversationIds = computed(
  () =>
    new Set(activeCards.value.map(card => card.conversationId).filter(Boolean))
);
const activeNonTerminalCard = computed(() =>
  activeCards.value.find(card => !card.terminal)
);

const isAbortError = error =>
  error?.name === 'AbortError' || error?.name === 'CanceledError';

const normalizeForSearch = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

const highlightSegments = (value, query, normalizedQuery) => {
  const text = String(value || '');
  const index = normalizedQuery
    ? normalizeForSearch(text).indexOf(normalizedQuery)
    : -1;

  if (index < 0) {
    return [{ text, highlighted: false }];
  }

  return [
    { text: text.slice(0, index), highlighted: false },
    { text: text.slice(index, index + query.length), highlighted: true },
    { text: text.slice(index + query.length), highlighted: false },
  ];
};

const contactDisplayName = contact =>
  contact?.name?.trim() || t('KANBAN.ADD_ITEM.UNKNOWN_CONTACT');

const contactDetails = contact =>
  [contact?.phoneNumber, contact?.email].filter(Boolean);
const contactDetailsSummary = contact =>
  contactDetails(contact).join(
    t('KANBAN.ADD_ITEM.CONTACT_DETAILS_SEPARATOR')
  ) || t('KANBAN.ADD_ITEM.NO_CONTACT_DETAILS');

const displayedContacts = computed(() => {
  const query = contactSearchQuery.value.trim();
  const normalizedQuery = normalizeForSearch(query);
  const contacts = isSearchActive.value
    ? searchResults.value
    : recentContacts.value;

  return contacts.map(contact => ({
    contact,
    nameSegments: highlightSegments(
      contactDisplayName(contact),
      query,
      normalizedQuery
    ),
    detailSegments: contactDetails(contact).map(detail =>
      highlightSegments(detail, query, normalizedQuery)
    ),
  }));
});

const inboxDisplayName = inbox =>
  inbox?.name?.trim() || t('KANBAN.CARD.UNKNOWN_INBOX');

const formatChannelType = channelType => {
  if (!channelType) return '';

  return channelType
    .split('::')
    .pop()
    .replace(/([A-Z])/g, ' $1')
    .trim();
};

const isInboxAllowed = inboxId =>
  props.inboxScopeMode !== 'selected_inboxes' ||
  props.allowedInboxIds.includes(inboxId);

const conversationInbox = conversation => {
  const inboxId = conversation?.inboxId;
  const getInboxById = store.getters?.['inboxes/getInboxById'];
  const inbox = getInboxById?.(inboxId) || {};

  return {
    ...inbox,
    id: inboxId,
    name: inbox.name || t('KANBAN.CARD.UNKNOWN_INBOX'),
    channelType: inbox.channelType || conversation?.meta?.channel || '',
  };
};

const conversationStatuses = computed(() => ({
  open: {
    label: t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.OPEN'),
    dotClass: 'bg-n-teal-9',
  },
  pending: {
    label: t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.PENDING'),
    dotClass: 'bg-n-amber-9',
  },
  resolved: {
    label: t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.RESOLVED'),
    dotClass: 'bg-n-slate-8',
  },
}));

const conversationStatus = status =>
  conversationStatuses.value[status] || conversationStatuses.value.resolved;

const lastConversationMessage = conversation =>
  conversation?.messages?.[0] || conversation?.lastNonActivityMessage;

const lastMessageAttachment = conversation =>
  lastConversationMessage(conversation)?.attachments?.[0];

const attachmentPreview = attachment =>
  attachment?.transcribedText ||
  attachment?.extension?.toUpperCase() ||
  attachment?.contentType?.split('/').pop()?.toUpperCase() ||
  attachment?.fileType ||
  '';

const conversationSnippet = conversation => {
  const message = lastConversationMessage(conversation);
  if (!message) return t('KANBAN.CARD.NO_MESSAGES');

  if (message.content) return message.content;

  const emailSubject = message.contentAttributes?.email?.subject;
  if (emailSubject) return emailSubject;

  return (
    attachmentPreview(lastMessageAttachment(conversation)) ||
    t('KANBAN.CARD.NO_MESSAGES')
  );
};

const lastMessageIsOutgoing = conversation => {
  const messageType = lastConversationMessage(conversation)?.messageType;

  return messageType !== undefined && messageType !== MESSAGE_TYPE.INCOMING;
};

const lastMessageAttachmentIcon = conversation =>
  ATTACHMENT_PREVIEW_ICONS[lastMessageAttachment(conversation)?.fileType] || '';

const lastActivityAt = conversation =>
  Number(conversation?.lastActivityAt || conversation?.timestamp || 0);

const conversationTimestamp = conversation => {
  const timestamp = lastActivityAt(conversation);

  return timestamp ? shortTimestamp(dynamicTime(timestamp), true) : '';
};

const selectedConversationTimestamp = conversation => {
  const timestamp = Number(
    lastConversationMessage(conversation)?.createdAt ||
      lastActivityAt(conversation)
  );

  return timestamp ? dateFormat(timestamp, 'dd/MM/yyyy HH:mm') : '';
};

const abortContactSearch = () => {
  contactSearchController.value?.abort();
  contactSearchController.value = null;
};

const abortContactDetails = () => {
  contactDetailsController.value?.abort();
  contactDetailsController.value = null;
};

const resetErrors = () => {
  subjectError.value = '';
  creationError.value = '';
};

const resetSubmission = () => {
  subject.value = '';
  isSaving.value = false;
  resetErrors();
};

const resetContactDetails = () => {
  abortContactDetails();
  conversations.value = [];
  hasMoreRecentConversations.value = false;
  contactableInboxes.value = [];
  selectedConversation.value = null;
  selectedFallbackInbox.value = null;
  activeCards.value = [];
  isLoadingContactDetails.value = false;
  contactDetailsError.value = false;
};

const loadRecentContacts = async () => {
  isLoadingRecentContacts.value = true;
  contactSearchError.value = false;

  try {
    const {
      data: { payload = [] },
    } = await ContactAPI.get(1, 'last_activity_at');

    recentContacts.value = camelcaseKeys(payload, { deep: true });
  } catch (error) {
    recentContacts.value = [];
    if (!isSearchActive.value) contactSearchError.value = true;
  } finally {
    isLoadingRecentContacts.value = false;
  }
};

const searchContacts = async query => {
  if (query !== contactSearchQuery.value.trim()) return;

  const controller = new AbortController();
  contactSearchController.value = controller;
  isSearchingContacts.value = true;
  contactSearchError.value = false;

  try {
    const {
      data: { payload },
    } = await ContactAPI.search(query, 1, 'name', '', {
      signal: controller.signal,
    });

    if (controller.signal.aborted) return;

    searchResults.value = camelcaseKeys(payload || [], { deep: true });
  } catch (error) {
    if (!isAbortError(error)) {
      contactSearchError.value = true;
      searchResults.value = [];
    }
  } finally {
    if (contactSearchController.value === controller) {
      contactSearchController.value = null;
      isSearchingContacts.value = false;
    }
  }
};

const debouncedSearchContacts = debounce(searchContacts, 300, false);

const onContactSearchInput = () => {
  abortContactSearch();
  contactSearchError.value = false;

  if (!isSearchActive.value) {
    searchResults.value = [];
    isSearchingContacts.value = false;
    return;
  }

  isSearchingContacts.value = true;
  debouncedSearchContacts(contactSearchQuery.value.trim());
};

const loadFallbackInboxes = async (contact, controller) => {
  const {
    data: { payload: rawInboxes = [] },
  } = await ContactAPI.getContactableInboxes(contact.id, {
    signal: controller.signal,
  });

  if (controller.signal.aborted) return;

  contactableInboxes.value = rawInboxes
    .map(item => ({
      ...camelcaseKeys(item.inbox, { deep: true }),
      sourceId: item.source_id,
    }))
    .filter(inbox => isInboxAllowed(inbox.id));
};

const loadContactDetails = async contact => {
  resetContactDetails();

  const controller = new AbortController();
  contactDetailsController.value = controller;
  isLoadingContactDetails.value = true;

  const [conversationsResult, cardsResult] = await Promise.allSettled([
    ContactAPI.getConversations(contact.id, { signal: controller.signal }),
    KanbanBoardsAPI.lookupCards(props.kanbanBoardId, {
      contactId: contact.id,
      signal: controller.signal,
    }),
  ]);

  if (controller.signal.aborted) return;

  if (cardsResult.status === 'fulfilled') {
    activeCards.value = camelcaseKeys(cardsResult.value.data || [], {
      deep: true,
    });
  }

  if (conversationsResult.status === 'fulfilled') {
    const rawConversations = conversationsResult.value.data?.payload || [];
    hasMoreRecentConversations.value =
      rawConversations.length === CONVERSATIONS_PAGE_SIZE;
    conversations.value = camelcaseKeys(rawConversations, { deep: true })
      .filter(conversation => isInboxAllowed(conversation.inboxId))
      .sort(
        (firstConversation, secondConversation) =>
          lastActivityAt(secondConversation) - lastActivityAt(firstConversation)
      )
      .map(conversation => ({
        ...conversation,
        inbox: conversationInbox(conversation),
      }));

    if (conversations.value.length === 0) {
      try {
        await loadFallbackInboxes(contact, controller);
      } catch (error) {
        if (!isAbortError(error)) contactDetailsError.value = true;
      }
    }
  } else if (!isAbortError(conversationsResult.reason)) {
    contactDetailsError.value = true;
  }

  if (contactDetailsController.value === controller) {
    contactDetailsController.value = null;
    isLoadingContactDetails.value = false;
  }
};

const selectContact = contact => {
  abortContactSearch();
  resetSubmission();
  selectedContact.value = contact;
  isSearchingContacts.value = false;
  contactSearchError.value = false;
  loadContactDetails(contact);
};

const selectConversation = conversation => {
  resetErrors();
  selectedFallbackInbox.value = null;
  selectedConversation.value = conversation;
};

const selectInbox = inbox => {
  resetErrors();
  selectedConversation.value = null;
  selectedFallbackInbox.value = inbox;
};

const changeContact = () => {
  resetContactDetails();
  resetSubmission();
  selectedContact.value = null;
  searchResults.value = [];
  contactSearchQuery.value = '';
};

const changeConversation = () => {
  resetErrors();
  selectedConversation.value = null;
  selectedFallbackInbox.value = null;
};

const goToStep = step => {
  if (step >= currentStep.value) return;

  if (step === 1) {
    changeContact();
    return;
  }

  changeConversation();
};

const serverErrorMessage = error =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  '';

const isDuplicateSubjectError = error =>
  serverErrorMessage(error)
    .toLowerCase()
    .includes('manual opportunity with this subject already exists');

const translatedCreationError = error => {
  const message = serverErrorMessage(error);

  if (message === 'terminal_stage_card_creation_not_allowed') {
    return t('KANBAN.ADD_ITEM.ERRORS.TERMINAL_STAGE');
  }

  if (message.toLowerCase().includes('inbox is not allowed by board scope')) {
    return t('KANBAN.ADD_ITEM.ERRORS.INBOX_NOT_ALLOWED');
  }

  return message || t('KANBAN.ADD_ITEM.ERRORS.GENERIC');
};

const createManualCard = async () => {
  if (isSaving.value) return;

  resetErrors();

  if (trimmedSubject.value.length < 3) {
    subjectError.value = t('KANBAN.ADD_ITEM.SUBJECT_MIN_LENGTH');
    return;
  }

  isSaving.value = true;

  const card = {
    kanban_stage_id: props.kanbanStageId,
    contact_id: selectedContact.value.id,
    subject: trimmedSubject.value,
  };

  if (selectedConversation.value) {
    card.conversation_display_id = selectedConversation.value.id;
  } else {
    card.inbox_id = selectedInbox.value.id;
  }

  try {
    const response = await KanbanBoardsAPI.createManualCard(
      props.kanbanBoardId,
      {
        card,
      }
    );
    emit('created', camelcaseKeys(response.data, { deep: true }));
  } catch (error) {
    if (isDuplicateSubjectError(error)) {
      subjectError.value = t('KANBAN.ADD_ITEM.ERRORS.DUPLICATE_SUBJECT');
    } else {
      creationError.value = translatedCreationError(error);
    }
  } finally {
    isSaving.value = false;
  }
};

const requestClose = () => emit('close');

watch(
  currentStep,
  step => {
    if (step === 1) contactSearchInputRef.value?.focus();
    if (step === 3) subjectInputRef.value?.focus();
  },
  { flush: 'post' }
);

onMounted(() => {
  contactSearchInputRef.value?.focus();
  loadRecentContacts();
});

onUnmounted(() => {
  abortContactSearch();
  abortContactDetails();
});

defineExpose({ hasUnsavedChanges });
</script>

<template>
  <div
    data-testid="kanban-add-item-panel"
    :data-stage-id="kanbanStageId"
    class="no-drag overflow-hidden rounded-lg border border-n-weak bg-n-surface-2"
  >
    <header class="border-b border-n-weak px-5 py-4">
      <div class="flex items-start justify-between gap-3">
        <h2
          data-testid="kanban-add-item-title"
          class="mb-0 text-base font-semibold text-n-slate-12"
        >
          {{ pickerTitle }}
        </h2>
        <Button
          ghost
          slate
          md
          icon="i-lucide-x"
          class="no-drag flex-shrink-0 [&>span]:size-5"
          :aria-label="t('KANBAN.ADD_ITEM.CLOSE')"
          @click="requestClose"
        />
      </div>
      <nav
        data-testid="kanban-picker-breadcrumb"
        class="mt-2 flex items-center gap-1 text-xs"
      >
        <template
          v-for="(step, index) in [
            { number: 1, label: t('KANBAN.ADD_ITEM.STEPS.CONTACT') },
            {
              number: 2,
              label: t('KANBAN.ADD_ITEM.STEPS.CONVERSATION'),
            },
            { number: 3, label: t('KANBAN.ADD_ITEM.STEPS.CARD') },
          ]"
          :key="step.number"
        >
          <button
            type="button"
            class="no-drag rounded-sm px-0.5 transition-colors disabled:cursor-default"
            :class="{
              'font-medium text-n-brand': currentStep === step.number,
              'text-n-slate-11 hover:text-n-slate-12':
                currentStep > step.number,
              'text-n-slate-9': currentStep < step.number,
            }"
            :disabled="currentStep < step.number"
            @click="goToStep(step.number)"
          >
            {{ step.label }}
          </button>
          <i
            v-if="index < 2"
            class="i-lucide-chevron-right size-3 text-n-slate-9"
          />
        </template>
      </nav>
    </header>

    <div class="p-5">
      <section v-if="currentStep === 1" data-testid="kanban-contact-step">
        <label :for="`kanban-contact-search-${kanbanStageId}`" class="sr-only">
          {{ t('KANBAN.ADD_ITEM.SEARCH_LABEL') }}
        </label>
        <Input
          :id="`kanban-contact-search-${kanbanStageId}`"
          ref="contactSearchInputRef"
          v-model="contactSearchQuery"
          type="search"
          data-testid="kanban-contact-search-input"
          class="group w-full"
          custom-input-class="no-drag !h-10 !rounded-md !bg-n-surface-1 !py-2 !pl-10 !pr-3"
          :placeholder="t('KANBAN.ADD_ITEM.PLACEHOLDER')"
          @input="onContactSearchInput"
        >
          <template #prefix>
            <Icon
              icon="i-lucide-search"
              class="pointer-events-none absolute top-1/2 size-4 -translate-y-1/2 text-n-slate-10 group-focus-within:text-n-brand ltr:left-3 rtl:right-3"
            />
          </template>
        </Input>

        <p
          v-if="isLoadingContacts"
          data-testid="kanban-contact-search-loading"
          class="mb-0 mt-4 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.ADD_ITEM.SEARCHING') }}
        </p>
        <p
          v-else-if="contactSearchError"
          data-testid="kanban-contact-search-error"
          class="mb-0 mt-4 text-sm text-n-ruby-11"
        >
          {{ t('KANBAN.ADD_ITEM.SEARCH_ERROR') }}
        </p>
        <div
          v-else-if="displayedContacts.length"
          data-testid="kanban-contact-search-results"
          class="mt-3 grid max-h-80 gap-1 overflow-y-auto"
        >
          <button
            v-for="row in displayedContacts"
            :key="row.contact.id"
            type="button"
            class="no-drag flex min-w-0 items-center gap-3 rounded-md p-2 text-left hover:bg-n-alpha-2"
            @click="selectContact(row.contact)"
          >
            <Avatar
              :name="contactDisplayName(row.contact)"
              :src="row.contact.thumbnail"
              :size="36"
              rounded-full
            />
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                <span
                  v-for="(segment, index) in row.nameSegments"
                  :key="`name-${index}`"
                  :class="{
                    'font-semibold text-n-brand': segment.highlighted,
                  }"
                >
                  {{ segment.text }}
                </span>
              </span>
              <span
                v-if="row.detailSegments.length"
                class="block truncate text-xs text-n-slate-11"
              >
                <template
                  v-for="(segments, detailIndex) in row.detailSegments"
                  :key="`detail-${detailIndex}`"
                >
                  <span v-if="detailIndex" class="px-1">{{
                    t('KANBAN.ADD_ITEM.CONTACT_DETAILS_SEPARATOR')
                  }}</span>
                  <span
                    v-for="(segment, index) in segments"
                    :key="`detail-${detailIndex}-${index}`"
                    :class="{
                      'font-semibold text-n-brand': segment.highlighted,
                    }"
                  >
                    {{ segment.text }}
                  </span>
                </template>
              </span>
              <span v-else class="block truncate text-xs text-n-slate-11">
                {{ t('KANBAN.ADD_ITEM.NO_CONTACT_DETAILS') }}
              </span>
            </span>
          </button>
        </div>
        <p
          v-else-if="isSearchActive"
          data-testid="kanban-contact-search-empty"
          class="mb-0 mt-4 text-sm text-n-slate-11"
        >
          {{
            t('KANBAN.ADD_ITEM.NO_CONTACTS_WITH_QUERY', {
              query: contactSearchQuery.trim(),
            })
          }}
        </p>
      </section>

      <section
        v-else-if="currentStep === 2"
        data-testid="kanban-conversation-step"
      >
        <button
          type="button"
          class="no-drag mb-4 inline-flex items-center gap-1.5 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="changeContact"
        >
          <i class="i-lucide-arrow-left size-3.5" />
          {{ t('KANBAN.ADD_ITEM.CHANGE_CONTACT') }}
        </button>

        <div class="mb-5 flex items-center gap-2.5">
          <Avatar
            :name="contactDisplayName(selectedContact)"
            :src="selectedContact.thumbnail"
            :size="36"
            rounded-full
          />
          <div class="min-w-0">
            <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
              {{ contactDisplayName(selectedContact) }}
            </p>
            <p class="mb-0 truncate text-xs text-n-slate-11">
              {{ contactDetailsSummary(selectedContact) }}
            </p>
          </div>
        </div>

        <p class="mb-3 text-sm text-n-slate-11">
          {{ t('KANBAN.ADD_ITEM.SELECT_CONVERSATION') }}
        </p>

        <p
          v-if="isLoadingContactDetails"
          data-testid="kanban-conversations-loading"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.ADD_ITEM.LOADING_INBOXES') }}
        </p>
        <p
          v-else-if="contactDetailsError"
          data-testid="kanban-conversations-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ t('KANBAN.ADD_ITEM.INBOXES_ERROR') }}
        </p>
        <template v-else>
          <div
            v-if="conversations.length"
            data-testid="kanban-conversation-list"
            class="grid gap-2"
          >
            <button
              v-for="conversation in conversations"
              :key="conversation.id"
              type="button"
              class="no-drag rounded-md border border-n-weak p-3 text-left hover:border-n-slate-6 hover:bg-n-alpha-1"
              @click="selectConversation(conversation)"
            >
              <span class="flex items-center justify-between gap-3">
                <span class="flex min-w-0 items-center gap-2">
                  <ChannelIcon
                    :inbox="conversation.inbox"
                    class="size-3.5 flex-shrink-0 text-n-slate-11"
                  />
                  <span class="truncate text-xs font-medium text-n-slate-11">
                    {{ inboxDisplayName(conversation.inbox) }}
                  </span>
                  <span
                    class="inline-flex items-center gap-1 text-xs text-n-slate-10"
                  >
                    <span
                      class="size-1.5 rounded-full"
                      :class="conversationStatus(conversation.status).dotClass"
                    />
                    {{ conversationStatus(conversation.status).label }}
                  </span>
                </span>
                <span class="flex flex-shrink-0 items-center gap-2">
                  <span
                    v-if="activeCardConversationIds.has(conversation.id)"
                    data-testid="kanban-conversation-has-card"
                    class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] text-n-slate-11"
                  >
                    {{ t('KANBAN.ADD_ITEM.HAS_CARD_BADGE') }}
                  </span>
                  <span class="text-[11px] text-n-slate-10">
                    {{ conversationTimestamp(conversation) }}
                  </span>
                </span>
              </span>
              <span class="mt-1.5 block truncate text-sm text-n-slate-12">
                {{ conversationSnippet(conversation) }}
              </span>
            </button>
          </div>
          <div v-else data-testid="kanban-fallback-inboxes">
            <p class="mb-3 text-sm text-n-slate-11">
              {{ t('KANBAN.ADD_ITEM.NO_ELIGIBLE_CONVERSATIONS') }}
            </p>
            <div v-if="contactableInboxes.length" class="grid gap-1">
              <button
                v-for="inbox in contactableInboxes"
                :key="inbox.id"
                type="button"
                class="no-drag flex min-w-0 items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-n-alpha-2"
                @click="selectInbox(inbox)"
              >
                <ChannelIcon
                  :inbox="inbox"
                  class="size-4 flex-shrink-0 text-n-slate-11"
                />
                <span class="min-w-0">
                  <span
                    class="block truncate text-sm font-medium text-n-slate-12"
                  >
                    {{ inboxDisplayName(inbox) }}
                  </span>
                  <span class="block truncate text-xs text-n-slate-11">
                    {{ formatChannelType(inbox.channelType) }}
                  </span>
                </span>
              </button>
            </div>
            <p
              v-else
              data-testid="kanban-inboxes-empty"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.ADD_ITEM.NO_INBOXES') }}
            </p>
          </div>
          <p
            v-if="hasMoreRecentConversations"
            data-testid="kanban-recent-conversations-note"
            class="mb-0 mt-3 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.ADD_ITEM.RECENT_CONVERSATIONS_NOTE') }}
          </p>
        </template>
      </section>

      <section v-else data-testid="kanban-card-step">
        <button
          type="button"
          class="no-drag mb-4 inline-flex items-center gap-1.5 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="changeConversation"
        >
          <i class="i-lucide-arrow-left size-3.5" />
          {{ t('KANBAN.ADD_ITEM.CHANGE_CONVERSATION') }}
        </button>

        <div
          data-testid="kanban-card-selection-summary"
          class="mb-5 flex min-w-0 items-center gap-3 rounded-md border border-n-weak bg-n-surface-1 p-3"
        >
          <div
            data-testid="kanban-card-selection-contact"
            class="relative flex-shrink-0"
          >
            <Avatar
              :name="contactDisplayName(selectedContact)"
              :src="selectedContact.thumbnail"
              :size="56"
              rounded-full
            />
            <span
              data-testid="kanban-card-selection-inbox"
              :title="inboxDisplayName(selectedInbox)"
              class="absolute -bottom-1 -right-1 flex size-6 cursor-help items-center justify-center rounded-full border-2 border-n-surface-1 bg-n-solid-1 text-n-slate-11"
            >
              <ChannelIcon :inbox="selectedInbox" class="size-3.5" />
            </span>
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex min-w-0 items-start justify-between gap-3">
              <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                {{ contactDisplayName(selectedContact) }}
              </p>
              <p
                v-if="selectedConversation"
                data-testid="kanban-card-selection-last-message-at"
                class="mb-0 flex-shrink-0 whitespace-nowrap text-xs text-n-slate-11"
              >
                {{ selectedConversationTimestamp(selectedConversation) }}
              </p>
            </div>
            <div
              v-if="selectedConversation"
              class="mt-1 flex min-w-0 items-center gap-1.5 text-sm text-n-slate-11"
            >
              <Icon
                v-if="lastMessageIsOutgoing(selectedConversation)"
                icon="i-lucide-check-check"
                class="size-3.5 flex-shrink-0"
              />
              <Icon
                v-if="lastMessageAttachmentIcon(selectedConversation)"
                :icon="lastMessageAttachmentIcon(selectedConversation)"
                class="size-3.5 flex-shrink-0"
              />
              <p
                data-testid="kanban-card-selection-last-message"
                class="mb-0 truncate"
              >
                {{ conversationSnippet(selectedConversation) }}
              </p>
            </div>
            <p v-else class="mb-0 mt-1 truncate text-sm text-n-slate-11">
              {{ formatChannelType(selectedInbox.channelType) }}
            </p>
          </div>
        </div>

        <p
          v-if="activeNonTerminalCard"
          data-testid="kanban-active-card-warning"
          class="mb-4 rounded-md bg-n-alpha-1 px-3 py-2 text-xs text-n-slate-11"
        >
          {{
            t('KANBAN.ADD_ITEM.ACTIVE_CARD_WARNING', {
              stageName: activeNonTerminalCard.stageName,
            })
          }}
        </p>

        <form
          data-testid="kanban-manual-card-form"
          class="grid gap-2 !p-0"
          @submit.prevent="createManualCard"
        >
          <label
            :for="`kanban-subject-${kanbanStageId}`"
            class="text-sm font-medium text-n-slate-12"
          >
            {{ t('KANBAN.ADD_ITEM.SUBJECT') }}
          </label>
          <input
            :id="`kanban-subject-${kanbanStageId}`"
            ref="subjectInputRef"
            v-model="subject"
            type="text"
            data-testid="kanban-manual-card-subject"
            class="no-drag min-h-10 w-full rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            :placeholder="t('KANBAN.ADD_ITEM.SUBJECT_PLACEHOLDER')"
            :aria-invalid="!!subjectError"
            @input="subjectError = ''"
          />
          <p
            v-if="subjectError"
            data-testid="kanban-manual-card-subject-error"
            class="mb-0 text-sm text-n-ruby-11"
          >
            {{ subjectError }}
          </p>
          <p class="mb-2 text-xs text-n-slate-10">
            {{ t('KANBAN.ADD_ITEM.SUBJECT_HINT') }}
          </p>
          <p
            v-if="creationError"
            data-testid="kanban-manual-card-error"
            class="mb-0 text-sm text-n-ruby-11"
          >
            {{ creationError }}
          </p>
          <div class="mt-2 flex items-center justify-end gap-2">
            <Button
              outline
              slate
              sm
              class="no-drag"
              :label="t('KANBAN.ADD_ITEM.BACK')"
              @click="changeConversation"
            />
            <Button
              sm
              type="submit"
              data-testid="kanban-manual-card-submit"
              class="no-drag"
              :label="
                isSaving
                  ? t('KANBAN.ADD_ITEM.SAVING')
                  : t('KANBAN.ADD_ITEM.CREATE_OPPORTUNITY')
              "
              :is-loading="isSaving"
              :disabled="isSaving || trimmedSubject.length < 3"
            />
          </div>
        </form>
      </section>
    </div>
  </div>
</template>
