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

const selectContact = contact => {
  abortContactSearch();
  selectedContact.value = contact;
  contactSearchResults.value = [];
  isSearchingContacts.value = false;
  contactSearchError.value = false;
};

const clearSelectedContact = () => {
  selectedContact.value = null;
};

onUnmounted(() => {
  abortContactSearch();
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
        @click="emit('close')"
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
            <p class="mb-0 mt-1 text-sm text-n-slate-11">
              {{ t('KANBAN.ADD_ITEM.CONVERSATIONS_NEXT_STEP') }}
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
