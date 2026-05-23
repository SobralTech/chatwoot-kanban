<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import camelcaseKeys from 'camelcase-keys';

import ContactNotesAPI from 'dashboard/api/contactNotes';
import { dynamicTime } from 'shared/helpers/timeHelper';
import ContactNoteItem from 'dashboard/components-next/Contacts/ContactsSidebar/components/ContactNoteItem.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  stages: {
    type: Array,
    required: true,
  },
  activeActionKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['moveCard', 'openConversation', 'removeCard']);

const { t } = useI18n();
const store = useStore();

const isNotesOpen = ref(false);
const isFetchingNotes = ref(false);
const isCreatingNote = ref(false);
const notesLoaded = ref(false);
const notes = ref([]);
const noteContent = ref('');

const conversation = computed(() => props.card.conversation || {});
const contact = computed(() => conversation.value?.meta?.sender || {});
const inbox = computed(() =>
  store.getters['inboxes/getInboxById'](conversation.value.inboxId)
);

const contactId = computed(() => contact.value?.id);
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
    conversation.value?.messages?.[0]?.content ||
    conversation.value?.lastNonActivityMessage?.content ||
    t('KANBAN.CARD.NO_MESSAGES')
);

const formattedNotes = computed(() =>
  notes.value.map(note => ({
    ...note,
    contactId: note.contactId || contactId.value,
  }))
);

const getWrittenBy = note => note?.user?.name || t('KANBAN.NOTES.BOT');

const fetchNotes = async () => {
  if (!contactId.value || notesLoaded.value || isFetchingNotes.value) return;

  isFetchingNotes.value = true;

  try {
    const response = await ContactNotesAPI.get(contactId.value);
    notes.value = camelcaseKeys(response.data || [], { deep: true });
    notesLoaded.value = true;
  } catch {
    useAlert(t('KANBAN.NOTES.FETCH_ERROR'));
  } finally {
    isFetchingNotes.value = false;
  }
};

const toggleNotes = async () => {
  isNotesOpen.value = !isNotesOpen.value;

  if (isNotesOpen.value) {
    await fetchNotes();
  }
};

const createNote = async () => {
  const content = noteContent.value.trim();
  if (!contactId.value || !content || isCreatingNote.value) return;

  isCreatingNote.value = true;

  try {
    const response = await ContactNotesAPI.create(contactId.value, content);
    notes.value = [
      camelcaseKeys(response.data || {}, { deep: true }),
      ...notes.value,
    ];
    noteContent.value = '';
    notesLoaded.value = true;
    useAlert(t('KANBAN.NOTES.CREATE_SUCCESS'));
  } catch {
    useAlert(t('KANBAN.NOTES.CREATE_ERROR'));
  } finally {
    isCreatingNote.value = false;
  }
};

const onMove = event => {
  emit('moveCard', props.card, event.target.value);
};
</script>

<template>
  <article class="rounded-lg border border-n-weak bg-n-surface-1 p-3">
    <button
      type="button"
      class="w-full text-left"
      :aria-label="
        t('KANBAN.CARD.OPEN_CONVERSATION', {
          contactName,
        })
      "
      @click="emit('openConversation', card, $event)"
    >
      <div class="flex items-start justify-between gap-2">
        <h4 class="min-w-0 truncate text-sm font-medium text-n-slate-12">
          {{ contactName }}
        </h4>
        <span class="flex-shrink-0 text-xs text-n-slate-10">
          {{ displayId }}
        </span>
      </div>

      <p class="mt-2 line-clamp-2 text-sm leading-5 text-n-slate-11">
        {{ lastMessage }}
      </p>
    </button>

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
        <span v-if="priority" class="flex-shrink-0 text-n-slate-10">
          {{ t('KANBAN.CARD.PRIORITY', { priority }) }}
        </span>
      </div>
      <span class="truncate text-n-slate-10">
        {{ t('KANBAN.CARD.LAST_ACTIVITY', { time: lastActivity }) }}
      </span>
    </div>

    <div class="mt-3 flex items-center gap-2">
      <select
        class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-2 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        :value="card.kanbanStageId"
        :disabled="!!activeActionKey"
        :aria-label="t('KANBAN.ACTIONS.MOVE_CARD')"
        @change="onMove"
      >
        <option
          v-for="targetStage in stages"
          :key="targetStage.id"
          :value="targetStage.id"
        >
          {{ targetStage.name }}
        </option>
      </select>

      <button
        type="button"
        class="flex-shrink-0 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-ruby-11 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!!activeActionKey"
        @click="emit('removeCard', card)"
      >
        {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
      </button>
    </div>

    <div class="mt-3 border-t border-n-weak pt-3">
      <button
        type="button"
        class="text-xs font-medium text-n-brand"
        :disabled="!contactId"
        @click="toggleNotes"
      >
        {{ isNotesOpen ? t('KANBAN.NOTES.HIDE') : t('KANBAN.NOTES.SHOW') }}
      </button>

      <div v-if="isNotesOpen" class="mt-3 grid gap-3">
        <p v-if="!contactId" class="text-sm text-n-slate-10">
          {{ t('KANBAN.NOTES.NO_CONTACT') }}
        </p>

        <template v-else>
          <form class="grid gap-2" @submit.prevent="createNote">
            <textarea
              v-model="noteContent"
              rows="3"
              class="min-w-0 resize-none rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="t('KANBAN.NOTES.PLACEHOLDER')"
            />
            <button
              type="submit"
              class="justify-self-start rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="!noteContent.trim() || isCreatingNote"
            >
              {{ t('KANBAN.NOTES.ADD') }}
            </button>
          </form>

          <p v-if="isFetchingNotes" class="text-sm text-n-slate-10">
            {{ t('KANBAN.NOTES.LOADING') }}
          </p>

          <div v-else-if="formattedNotes.length > 0" class="grid gap-3">
            <ContactNoteItem
              v-for="note in formattedNotes"
              :key="note.id"
              :note="note"
              :written-by="getWrittenBy(note)"
              collapsible
            />
          </div>

          <p v-else class="text-sm text-n-slate-10">
            {{ t('KANBAN.NOTES.EMPTY') }}
          </p>
        </template>
      </div>
    </div>
  </article>
</template>
