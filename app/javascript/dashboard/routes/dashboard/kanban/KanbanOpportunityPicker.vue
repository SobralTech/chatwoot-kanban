<script setup>
import { ref, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import { debounce } from '@chatwoot/utils';
import ContactAPI from 'dashboard/api/contacts';

defineProps({
  kanbanStageId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const contactSearchQuery = ref('');
const contactSearchResults = ref([]);
const selectedContact = ref(null);
const isSearchingContacts = ref(false);
const hasSearchedContacts = ref(false);
const contactSearchError = ref(false);
const contactSearchController = ref(null);
const contactSearchMinimumLength = 3;

const contactableInboxes = ref([]);
const isLoadingInboxes = ref(false);
const inboxesError = ref(false);
const selectedInbox = ref(null);
const inboxesController = ref(null);

const isAbortError = error =>
  error?.name === 'AbortError' || error?.name === 'CanceledError';

const abortContactSearch = () => {
  contactSearchController.value?.abort();
  contactSearchController.value = null;
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
  selectedContact.value = null;
  contactSearchError.value = false;

  const trimmedQuery = contactSearchQuery.value.trim();
  if (trimmedQuery.length < contactSearchMinimumLength) {
    contactSearchResults.value = [];
    hasSearchedContacts.value = false;
    isSearchingContacts.value = false;
    return;
  }

  isSearchingContacts.value = true;
  debouncedSearchContacts(trimmedQuery);
};

const formatChannelType = channelType => {
  if (!channelType) return '';
  return channelType
    .split('::')
    .pop()
    .replace(/([A-Z])/g, ' $1')
    .trim();
};

const resetInboxes = () => {
  inboxesController.value?.abort();
  inboxesController.value = null;
  contactableInboxes.value = [];
  isLoadingInboxes.value = false;
  inboxesError.value = false;
  selectedInbox.value = null;
};

const loadContactableInboxes = async contact => {
  resetInboxes();

  const controller = new AbortController();
  inboxesController.value = controller;
  isLoadingInboxes.value = true;

  try {
    const {
      data: { payload: rawInboxes = [] },
    } = await ContactAPI.getContactableInboxes(contact.id, {
      signal: controller.signal,
    });

    if (controller.signal.aborted) return;

    contactableInboxes.value = (rawInboxes || []).map(item => ({
      ...camelcaseKeys(item.inbox, { deep: true }),
      sourceId: item.source_id,
    }));
  } catch (error) {
    if (!isAbortError(error)) {
      inboxesError.value = true;
      contactableInboxes.value = [];
    }
  } finally {
    if (inboxesController.value === controller) {
      isLoadingInboxes.value = false;
    }
  }
};

const selectInbox = inbox => {
  selectedInbox.value = inbox;
};

const handleClose = () => {
  resetInboxes();
  emit('close');
};

const selectContact = contact => {
  abortContactSearch();
  selectedContact.value = contact;
  contactSearchResults.value = [];
  isSearchingContacts.value = false;
  contactSearchError.value = false;
  loadContactableInboxes(contact);
};

const clearSelectedContact = () => {
  resetInboxes();
  selectedContact.value = null;
};

onUnmounted(() => {
  abortContactSearch();
  resetInboxes();
});
</script>

<template>
  <div
    data-testid="kanban-add-item-panel"
    :data-stage-id="kanbanStageId"
    class="no-drag rounded-lg border border-n-weak bg-n-surface-2 p-3"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0 flex-1">
        <label :for="`kanban-contact-search-${kanbanStageId}`" class="sr-only">
          {{ t('KANBAN.ADD_ITEM.SEARCH_LABEL') }}
        </label>
        <div>
          <input
            :id="`kanban-contact-search-${kanbanStageId}`"
            v-model="contactSearchQuery"
            type="search"
            data-testid="kanban-contact-search-input"
            class="no-drag min-h-10 w-full rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            :placeholder="t('KANBAN.ADD_ITEM.PLACEHOLDER')"
            @input="onContactSearchInput"
          />
        </div>
      </div>
      <button
        type="button"
        class="mt-1 flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('KANBAN.ADD_ITEM.CLOSE')"
        @click="handleClose"
      >
        <i class="i-lucide-x size-4" />
      </button>
    </div>

    <div class="mt-3">
      <div
        v-if="selectedContact"
        data-testid="kanban-selected-contact"
        class="rounded-md border border-n-weak bg-n-surface-1 p-3"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
              {{ selectedContact.name }}
            </p>
          </div>
          <button
            type="button"
            class="flex size-7 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :aria-label="t('KANBAN.ADD_ITEM.CLEAR_CONTACT')"
            @click="clearSelectedContact"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </div>
      </div>

      <div v-if="selectedContact" class="mt-3">
        <p
          v-if="isLoadingInboxes"
          data-testid="kanban-inboxes-loading"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.ADD_ITEM.LOADING_INBOXES') }}
        </p>

        <p
          v-else-if="inboxesError"
          data-testid="kanban-inboxes-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ t('KANBAN.ADD_ITEM.INBOXES_ERROR') }}
        </p>

        <p
          v-else-if="contactableInboxes.length === 0"
          data-testid="kanban-inboxes-empty"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.ADD_ITEM.NO_INBOXES') }}
        </p>

        <div v-else data-testid="kanban-inboxes" class="grid gap-1">
          <button
            v-for="inbox in contactableInboxes"
            :key="inbox.id"
            type="button"
            class="no-drag flex min-w-0 items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-n-alpha-2"
            :class="{
              'bg-n-alpha-2 ring-1 ring-n-brand':
                selectedInbox?.id === inbox.id,
            }"
            @click="selectInbox(inbox)"
          >
            <img
              v-if="inbox.avatarUrl"
              :src="inbox.avatarUrl"
              :alt="inbox.name"
              class="size-8 flex-shrink-0 rounded-full object-cover"
            />
            <span
              v-else
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-xs font-medium text-n-slate-11"
            >
              {{ inbox.name?.charAt(0) || '?' }}
            </span>
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ inbox.name }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ formatChannelType(inbox.channelType) }}
              </span>
            </span>
          </button>
        </div>
      </div>

      <p
        v-else-if="isSearchingContacts"
        data-testid="kanban-contact-search-loading"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.ADD_ITEM.SEARCHING') }}
      </p>

      <p
        v-else-if="contactSearchError"
        data-testid="kanban-contact-search-error"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ t('KANBAN.ADD_ITEM.SEARCH_ERROR') }}
      </p>

      <div
        v-else-if="contactSearchResults.length > 0"
        data-testid="kanban-contact-search-results"
        class="grid gap-1"
      >
        <button
          v-for="contact in contactSearchResults"
          :key="contact.id"
          type="button"
          class="no-drag flex min-w-0 items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-n-alpha-2"
          @click="selectContact(contact)"
        >
          <img
            v-if="contact.thumbnail"
            :src="contact.thumbnail"
            :alt="contact.name"
            class="size-8 flex-shrink-0 rounded-full object-cover"
          />
          <span
            v-else
            class="flex size-8 flex-shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-xs font-medium text-n-slate-11"
          >
            {{ contact.name?.charAt(0) || '?' }}
          </span>
          <span class="min-w-0">
            <span class="block truncate text-sm font-medium text-n-slate-12">
              {{ contact.name || t('KANBAN.ADD_ITEM.UNKNOWN_CONTACT') }}
            </span>
            <span
              v-if="contact.email"
              class="block truncate text-xs text-n-slate-11"
            >
              {{ contact.email }}
            </span>
            <span
              v-if="contact.phoneNumber"
              class="block truncate text-xs text-n-slate-11"
            >
              {{ contact.phoneNumber }}
            </span>
            <span
              v-if="!contact.email && !contact.phoneNumber"
              class="block truncate text-xs text-n-slate-11"
            >
              {{ t('KANBAN.ADD_ITEM.NO_CONTACT_DETAILS') }}
            </span>
          </span>
        </button>
      </div>

      <p
        v-else-if="hasSearchedContacts"
        data-testid="kanban-contact-search-empty"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.ADD_ITEM.NO_CONTACTS') }}
      </p>
    </div>
  </div>
</template>
