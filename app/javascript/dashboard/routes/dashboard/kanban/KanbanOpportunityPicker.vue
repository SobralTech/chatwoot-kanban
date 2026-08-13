<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { debounce } from '@chatwoot/utils';
import { useStore } from 'dashboard/composables/store';
import ContactAPI from 'dashboard/api/contacts';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

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

const currentStep = ref(1);
const contactSearchQuery = ref('');
const recentContacts = ref([]);
const contactSearchResults = ref([]);
const selectedContact = ref(null);
const isSearchingContacts = ref(false);
const isLoadingRecentContacts = ref(false);
const hasSearchedContacts = ref(false);
const contactSearchError = ref(false);
const contactSearchController = ref(null);
const contactSearchMinimumLength = 2;

const conversations = ref([]);
const fetchedConversationsCount = ref(0);
const contactableInboxes = ref([]);
const selectedConversation = ref(null);
const selectedInbox = ref(null);
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
const isLoadingContacts = computed(
  () => isLoadingRecentContacts.value || isSearchingContacts.value
);
const hasRecentConversationsNote = computed(
  () => fetchedConversationsCount.value === 20
);
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

const highlightSegments = (value, query) => {
  const text = String(value || '');
  const normalizedQuery = normalizeForSearch(query.trim());
  const index = normalizeForSearch(text).indexOf(normalizedQuery);

  if (!normalizedQuery || index < 0) {
    return [{ text, highlighted: false }];
  }

  return [
    { text: text.slice(0, index), highlighted: false },
    {
      text: text.slice(index, index + query.trim().length),
      highlighted: true,
    },
    {
      text: text.slice(index + query.trim().length),
      highlighted: false,
    },
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

const conversationStatusLabel = status => {
  if (status === 'open') {
    return t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.OPEN');
  }

  if (status === 'pending') {
    return t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.PENDING');
  }

  return t('KANBAN.ADD_ITEM.CONVERSATION_STATUS.RESOLVED');
};

const conversationStatusClass = status => {
  switch (status) {
    case 'open':
      return 'bg-n-teal-9';
    case 'pending':
      return 'bg-n-amber-9';
    default:
      return 'bg-n-slate-8';
  }
};

const conversationSnippet = conversation =>
  conversation?.messages?.[0]?.content || t('KANBAN.CARD.NO_MESSAGES');

const conversationTimestamp = conversation => {
  const timestamp = Number(
    conversation?.lastActivityAt || conversation?.timestamp
  );

  return timestamp ? shortTimestamp(dynamicTime(timestamp), true) : '';
};

const abortContactSearch = () => {
  contactSearchController.value?.abort();
  contactSearchController.value = null;
};

const abortContactDetails = () => {
  contactDetailsController.value?.abort();
  contactDetailsController.value = null;
};

const resetSubmission = () => {
  subject.value = '';
  subjectError.value = '';
  creationError.value = '';
  isSaving.value = false;
};

const resetContactDetails = () => {
  abortContactDetails();
  conversations.value = [];
  fetchedConversationsCount.value = 0;
  contactableInboxes.value = [];
  selectedConversation.value = null;
  selectedInbox.value = null;
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
    if (contactSearchQuery.value.trim().length < contactSearchMinimumLength) {
      contactSearchResults.value = recentContacts.value;
    }
  } catch (error) {
    if (contactSearchQuery.value.trim().length < contactSearchMinimumLength) {
      contactSearchError.value = true;
      contactSearchResults.value = [];
    }
    recentContacts.value = [];
  } finally {
    isLoadingRecentContacts.value = false;
  }
};

const searchContacts = async query => {
  const trimmedQuery = query.trim();
  if (
    trimmedQuery.length < contactSearchMinimumLength ||
    trimmedQuery !== contactSearchQuery.value.trim()
  ) {
    return;
  }

  const controller = new AbortController();
  contactSearchController.value = controller;
  isSearchingContacts.value = true;
  hasSearchedContacts.value = true;
  contactSearchError.value = false;

  try {
    const {
      data: { payload },
    } = await ContactAPI.search(trimmedQuery, 1, 'name', '', {
      signal: controller.signal,
    });

    if (controller.signal.aborted) return;

    contactSearchResults.value = camelcaseKeys(payload || [], { deep: true });
  } catch (error) {
    if (!isAbortError(error)) {
      contactSearchError.value = true;
      contactSearchResults.value = [];
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

  const trimmedQuery = contactSearchQuery.value.trim();
  if (trimmedQuery.length < contactSearchMinimumLength) {
    contactSearchResults.value = recentContacts.value;
    hasSearchedContacts.value = false;
    isSearchingContacts.value = false;
    return;
  }

  isSearchingContacts.value = true;
  debouncedSearchContacts(trimmedQuery);
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
    KanbanBoardsAPI.lookupCards(props.kanbanBoardId, { contactId: contact.id }),
  ]);

  if (controller.signal.aborted) return;

  if (cardsResult.status === 'fulfilled') {
    const payload = cardsResult.value.data?.payload ?? cardsResult.value.data;
    activeCards.value = camelcaseKeys(payload || [], { deep: true });
  }

  if (conversationsResult.status === 'fulfilled') {
    const rawConversations = conversationsResult.value.data?.payload || [];
    fetchedConversationsCount.value = rawConversations.length;
    conversations.value = camelcaseKeys(rawConversations, { deep: true })
      .filter(conversation => isInboxAllowed(conversation.inboxId))
      .sort(
        (firstConversation, secondConversation) =>
          Number(
            secondConversation.lastActivityAt ||
              secondConversation.timestamp ||
              0
          ) -
          Number(
            firstConversation.lastActivityAt || firstConversation.timestamp || 0
          )
      );

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
  contactSearchResults.value = [];
  isSearchingContacts.value = false;
  contactSearchError.value = false;
  currentStep.value = 2;
  loadContactDetails(contact);
};

const selectConversation = conversation => {
  selectedConversation.value = conversation;
  selectedInbox.value = conversationInbox(conversation);
  subjectError.value = '';
  creationError.value = '';
  currentStep.value = 3;
};

const selectInbox = inbox => {
  selectedConversation.value = null;
  selectedInbox.value = inbox;
  subjectError.value = '';
  creationError.value = '';
  currentStep.value = 3;
};

const changeContact = () => {
  resetContactDetails();
  resetSubmission();
  selectedContact.value = null;
  contactSearchResults.value = recentContacts.value;
  contactSearchQuery.value = '';
  hasSearchedContacts.value = false;
  currentStep.value = 1;
};

const changeConversation = () => {
  selectedConversation.value = null;
  selectedInbox.value = null;
  subjectError.value = '';
  creationError.value = '';
  currentStep.value = 2;
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

  subjectError.value = '';
  creationError.value = '';

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

watch(currentStep, step => {
  nextTick(() => {
    if (step === 1) contactSearchInputRef.value?.focus();
    if (step === 3) subjectInputRef.value?.focus();
  });
});

onMounted(() => {
  contactSearchInputRef.value?.focus();
  loadRecentContacts();
});

onUnmounted(() => {
  abortContactSearch();
  abortContactDetails();
});

defineExpose({
  hasUnsavedSubject: () => trimmedSubject.value.length > 0,
});
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
          {{
            t('KANBAN.ADD_ITEM.TITLE_WITH_STAGE', {
              stageName: kanbanStageName,
            })
          }}
        </h2>
        <button
          type="button"
          class="no-drag flex size-7 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('KANBAN.ADD_ITEM.CLOSE')"
          @click="requestClose"
        >
          <i class="i-lucide-x size-4" />
        </button>
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
        <div class="relative">
          <i
            class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            :id="`kanban-contact-search-${kanbanStageId}`"
            ref="contactSearchInputRef"
            v-model="contactSearchQuery"
            type="search"
            data-testid="kanban-contact-search-input"
            class="no-drag min-h-10 w-full rounded-md border border-n-weak bg-n-surface-1 py-2 pl-9 pr-3 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            :placeholder="t('KANBAN.ADD_ITEM.PLACEHOLDER')"
            @input="onContactSearchInput"
          />
        </div>

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
          v-else-if="contactSearchResults.length"
          data-testid="kanban-contact-search-results"
          class="mt-3 grid max-h-80 gap-1 overflow-y-auto"
        >
          <button
            v-for="contact in contactSearchResults"
            :key="contact.id"
            type="button"
            class="no-drag flex min-w-0 items-center gap-3 rounded-md p-2 text-left hover:bg-n-alpha-2"
            @click="selectContact(contact)"
          >
            <Avatar
              :name="contactDisplayName(contact)"
              :src="contact.thumbnail"
              :size="36"
              rounded-full
            />
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                <template
                  v-for="(segment, index) in highlightSegments(
                    contactDisplayName(contact),
                    contactSearchQuery
                  )"
                  :key="`${contact.id}-name-${index}`"
                >
                  <span
                    :class="{
                      'font-semibold text-n-brand': segment.highlighted,
                    }"
                  >
                    {{ segment.text }}
                  </span>
                </template>
              </span>
              <span
                v-if="contactDetails(contact).length"
                class="block truncate text-xs text-n-slate-11"
              >
                <template
                  v-for="(detail, index) in contactDetails(contact)"
                  :key="`${contact.id}-detail-${detail}`"
                >
                  <span v-if="index" class="px-1">{{
                    t('KANBAN.ADD_ITEM.CONTACT_DETAILS_SEPARATOR')
                  }}</span>
                  <template
                    v-for="(segment, segmentIndex) in highlightSegments(
                      detail,
                      contactSearchQuery
                    )"
                    :key="`${contact.id}-detail-${index}-${segmentIndex}`"
                  >
                    <span
                      :class="{
                        'font-semibold text-n-brand': segment.highlighted,
                      }"
                    >
                      {{ segment.text }}
                    </span>
                  </template>
                </template>
              </span>
              <span v-else class="block truncate text-xs text-n-slate-11">
                {{ t('KANBAN.ADD_ITEM.NO_CONTACT_DETAILS') }}
              </span>
            </span>
          </button>
        </div>
        <p
          v-else-if="hasSearchedContacts"
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
        v-else-if="currentStep === 2 && selectedContact"
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
        <template v-else-if="conversations.length">
          <div data-testid="kanban-conversation-list" class="grid gap-2">
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
                    :inbox="conversationInbox(conversation)"
                    class="size-3.5 flex-shrink-0 text-n-slate-11"
                  />
                  <span class="truncate text-xs font-medium text-n-slate-11">
                    {{ inboxDisplayName(conversationInbox(conversation)) }}
                  </span>
                  <span
                    class="inline-flex items-center gap-1 text-xs text-n-slate-10"
                  >
                    <span
                      class="size-1.5 rounded-full"
                      :class="conversationStatusClass(conversation.status)"
                    />
                    {{ conversationStatusLabel(conversation.status) }}
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
          <p
            v-if="hasRecentConversationsNote"
            data-testid="kanban-recent-conversations-note"
            class="mb-0 mt-3 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.ADD_ITEM.RECENT_CONVERSATIONS_NOTE') }}
          </p>
        </template>
        <template v-else>
          <div data-testid="kanban-fallback-inboxes">
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
            v-if="hasRecentConversationsNote"
            data-testid="kanban-recent-conversations-note"
            class="mb-0 mt-3 text-xs text-n-slate-10"
          >
            {{ t('KANBAN.ADD_ITEM.RECENT_CONVERSATIONS_NOTE') }}
          </p>
        </template>
      </section>

      <section
        v-else-if="currentStep === 3 && selectedContact && selectedInbox"
        data-testid="kanban-card-step"
      >
        <button
          type="button"
          class="no-drag mb-4 inline-flex items-center gap-1.5 text-xs text-n-slate-11 hover:text-n-slate-12"
          @click="changeConversation"
        >
          <i class="i-lucide-arrow-left size-3.5" />
          {{ t('KANBAN.ADD_ITEM.CHANGE_CONVERSATION') }}
        </button>

        <div class="mb-4 rounded-md border border-n-weak bg-n-surface-1 p-3">
          <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
            {{ contactDisplayName(selectedContact) }}
          </p>
          <p class="mb-0 mt-1 truncate text-xs text-n-slate-11">
            {{
              selectedConversation
                ? conversationSnippet(selectedConversation)
                : inboxDisplayName(selectedInbox)
            }}
          </p>
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
          class="grid gap-2"
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
            <button
              type="button"
              class="no-drag min-h-10 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-11 hover:border-n-slate-6 hover:text-n-slate-12"
              @click="changeConversation"
            >
              {{ t('KANBAN.ADD_ITEM.BACK') }}
            </button>
            <button
              type="submit"
              data-testid="kanban-manual-card-submit"
              class="no-drag flex min-h-10 items-center justify-center gap-2 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="isSaving || trimmedSubject.length < 3"
            >
              <i
                v-if="isSaving"
                class="i-lucide-loader-2 size-4 animate-spin"
              />
              {{
                isSaving
                  ? t('KANBAN.ADD_ITEM.SAVING')
                  : t('KANBAN.ADD_ITEM.CREATE_OPPORTUNITY')
              }}
            </button>
          </div>
        </form>
      </section>
    </div>
  </div>
</template>
