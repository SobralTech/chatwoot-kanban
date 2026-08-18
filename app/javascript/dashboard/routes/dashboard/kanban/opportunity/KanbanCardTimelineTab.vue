<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import camelcaseKeys from 'camelcase-keys';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
  cardId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');

const PAGE_LIMIT = 20;
const MAX_ATTACHMENTS = 5;
const MAX_ATTACHMENT_SIZE = 20 * 1024 * 1024;

const timelineItems = ref([]);
const eventHasMore = ref(true);
const noteHasMore = ref(true);
const eventCursor = ref(null);
const noteCursor = ref(null);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const loadError = ref('');

const noteContent = ref('');
const selectedFiles = ref([]);
const attachmentInput = ref(null);
const isSavingNote = ref(false);
const editingNoteId = ref(null);
const editingContent = ref('');
const isSavingEdit = ref(false);
const deleteDialogRef = ref(null);
const notePendingDeletion = ref(null);

const hasMore = computed(() => eventHasMore.value || noteHasMore.value);

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.message || fallback;

const sortTimelineItems = items =>
  [...items].sort((first, second) => {
    const createdAtDifference = second.createdAt - first.createdAt;
    if (createdAtDifference !== 0) return createdAtDifference;

    return second.id - first.id;
  });

const normalizeItem = (item, itemType) => ({ ...item, itemType });

const pageParams = cursor =>
  cursor ? { limit: PAGE_LIMIT, before_id: cursor } : { limit: PAGE_LIMIT };

const emptyPage = () =>
  Promise.resolve({
    data: { payload: [], has_more: false, next_cursor: null },
  });

const loadPage = (loader, sourceHasMore, cursor, loadMore) => {
  if (loadMore && !sourceHasMore) return emptyPage();

  return loader(
    props.boardId,
    props.cardId,
    loadMore ? pageParams(cursor) : { limit: PAGE_LIMIT }
  );
};

const loadEvents = async (loadMore = false) => {
  if (loadMore) {
    isLoadingMore.value = true;
  } else {
    isLoading.value = true;
    loadError.value = '';
  }

  try {
    const [eventsResponse, notesResponse] = await Promise.all([
      loadPage(
        KanbanBoardsAPI.getCardEvents.bind(KanbanBoardsAPI),
        eventHasMore.value,
        eventCursor.value,
        loadMore
      ),
      loadPage(
        KanbanBoardsAPI.getCardNotes.bind(KanbanBoardsAPI),
        noteHasMore.value,
        noteCursor.value,
        loadMore
      ),
    ]);
    const eventsPayload = camelcaseKeys(eventsResponse.data || {}, {
      deep: true,
    });
    const notesPayload = camelcaseKeys(notesResponse.data || {}, {
      deep: true,
    });
    const fetchedItems = [
      ...(eventsPayload.payload || []).map(event =>
        normalizeItem(event, 'event')
      ),
      ...(notesPayload.payload || []).map(note => normalizeItem(note, 'note')),
    ];

    timelineItems.value = sortTimelineItems(
      loadMore ? [...timelineItems.value, ...fetchedItems] : fetchedItems
    );
    eventHasMore.value = !!eventsPayload.hasMore;
    noteHasMore.value = !!notesPayload.hasMore;
    eventCursor.value = eventsPayload.nextCursor;
    noteCursor.value = notesPayload.nextCursor;
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_ERROR')
    );
    if (!loadMore) useAlert(loadError.value);
  } finally {
    isLoading.value = false;
    isLoadingMore.value = false;
  }
};

const orUnknown = value =>
  value || t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.UNKNOWN_VALUE');

const priorityLabel = priority =>
  t(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`);

const dueDateLabel = dueAt => format(new Date(dueAt), 'dd/MM/yyyy');

const productLabel = metadata => orUnknown(metadata.name || metadata.sku);

const EVENT_MESSAGES = {
  card_created: () => ['CARD_CREATED'],
  card_deleted: () => ['CARD_DELETED'],
  reopened: () => ['REOPENED'],
  assignees_changed: () => ['ASSIGNEES_CHANGED'],
  labels_changed: () => ['LABELS_CHANGED'],
  stage_changed: metadata => [
    'STAGE_CHANGED',
    {
      from: orUnknown(metadata.fromStageName || metadata.fromStageId),
      to: orUnknown(metadata.toStageName || metadata.toStageId),
    },
  ],
  won: metadata =>
    metadata.reasonTitle
      ? ['WON', { reason: metadata.reasonTitle }]
      : ['WON_NO_REASON'],
  lost: metadata =>
    metadata.reasonTitle
      ? ['LOST', { reason: metadata.reasonTitle }]
      : ['LOST_NO_REASON'],
  priority_changed: metadata =>
    metadata.to
      ? ['PRIORITY_CHANGED', { to: priorityLabel(metadata.to) }]
      : ['PRIORITY_CLEARED'],
  due_at_changed: metadata =>
    metadata.to
      ? ['DUE_AT_CHANGED', { to: dueDateLabel(metadata.to) }]
      : ['DUE_AT_CLEARED'],
  product_added: metadata => [
    'PRODUCT_ADDED',
    { quantity: metadata.quantity, name: productLabel(metadata) },
  ],
  product_removed: metadata => [
    'PRODUCT_REMOVED',
    { name: productLabel(metadata) },
  ],
  product_price_changed: metadata => [
    'PRODUCT_PRICE_CHANGED',
    { name: productLabel(metadata) },
  ],
  product_quantity_changed: metadata => [
    'PRODUCT_QUANTITY_CHANGED',
    { name: productLabel(metadata) },
  ],
};

const eventMessage = event => {
  const buildMessage = EVENT_MESSAGES[event.eventType];
  const [key, params = {}] = buildMessage
    ? buildMessage(event.metadata || {})
    : ['UNKNOWN'];

  return t(`KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EVENTS.${key}`, params);
};

const eventTimestamp = item =>
  shortTimestamp(dynamicTime(item.createdAt), true);

const canManageNote = note =>
  isAdmin.value || note.user?.id === currentUser.value?.id;

const isImageAttachment = attachment =>
  attachment.contentType?.startsWith('image/');

const formatFileSize = bytes => {
  if (!bytes) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
};

const handleAttachmentChange = event => {
  const files = Array.from(event.target.files || []);
  const validFiles = files.filter(file => file.size <= MAX_ATTACHMENT_SIZE);

  if (validFiles.length !== files.length) {
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACHMENT_TOO_LARGE'));
  }

  const availableSlots = MAX_ATTACHMENTS - selectedFiles.value.length;
  if (validFiles.length > availableSlots) {
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.TOO_MANY_ATTACHMENTS'));
  }

  selectedFiles.value = [
    ...selectedFiles.value,
    ...validFiles.slice(0, Math.max(availableSlots, 0)),
  ];
  event.target.value = '';
};

const removeSelectedFile = index => {
  selectedFiles.value = selectedFiles.value.filter(
    (_file, fileIndex) => fileIndex !== index
  );
};

const saveNote = async () => {
  if (!noteContent.value.trim() || isSavingNote.value) return;

  isSavingNote.value = true;
  const payload = new FormData();
  payload.append('note[content]', noteContent.value);
  selectedFiles.value.forEach(file =>
    payload.append('note[attachments][]', file)
  );

  try {
    const response = await KanbanBoardsAPI.createCardNote(
      props.boardId,
      props.cardId,
      payload
    );
    const note = camelcaseKeys(response.data || {}, { deep: true });
    timelineItems.value = sortTimelineItems([
      normalizeItem(note, 'note'),
      ...timelineItems.value,
    ]);
    noteContent.value = '';
    selectedFiles.value = [];
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_SAVED'));
  } catch (error) {
    useAlert(
      getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_ERROR')
      )
    );
  } finally {
    isSavingNote.value = false;
  }
};

const startEditingNote = note => {
  editingNoteId.value = note.id;
  editingContent.value = note.content;
};

const cancelEditingNote = () => {
  editingNoteId.value = null;
  editingContent.value = '';
};

const saveNoteEdit = async note => {
  if (!editingContent.value.trim() || isSavingEdit.value) return;

  isSavingEdit.value = true;
  try {
    const response = await KanbanBoardsAPI.updateCardNote(
      props.boardId,
      props.cardId,
      note.id,
      { content: editingContent.value }
    );
    const updatedNote = normalizeItem(
      camelcaseKeys(response.data || {}, { deep: true }),
      'note'
    );
    timelineItems.value = sortTimelineItems(
      timelineItems.value.map(item =>
        item.itemType === 'note' && item.id === note.id ? updatedNote : item
      )
    );
    cancelEditingNote();
  } catch (error) {
    useAlert(
      getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_ERROR')
      )
    );
  } finally {
    isSavingEdit.value = false;
  }
};

const requestDeleteNote = note => {
  notePendingDeletion.value = note;
  deleteDialogRef.value?.open();
};

const confirmDeleteNote = async () => {
  const note = notePendingDeletion.value;
  if (!note) return;

  try {
    await KanbanBoardsAPI.deleteCardNote(props.boardId, props.cardId, note.id);
    timelineItems.value = timelineItems.value.filter(
      item => !(item.itemType === 'note' && item.id === note.id)
    );
  } catch (error) {
    useAlert(
      getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_ERROR')
      )
    );
  } finally {
    notePendingDeletion.value = null;
    deleteDialogRef.value?.close();
  }
};

onMounted(() => loadEvents());
</script>

<template>
  <section
    data-testid="kanban-opportunity-timeline-tab"
    class="grid min-w-0 gap-4"
  >
    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.TAB_TITLE') }}
    </h3>

    <form
      class="grid gap-3 rounded-lg border border-n-weak p-3"
      data-testid="kanban-opportunity-note-form"
      @submit.prevent="saveNote"
    >
      <textarea
        v-model="noteContent"
        rows="3"
        class="w-full resize-y rounded-md border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_PLACEHOLDER')"
        data-testid="kanban-opportunity-note-input"
      />
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <input
            ref="attachmentInput"
            type="file"
            multiple
            class="hidden"
            @change="handleAttachmentChange"
          />
          <button
            type="button"
            class="rounded-md border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1 focus:outline-none focus:ring-1 focus:ring-n-brand"
            data-testid="kanban-opportunity-note-attach"
            :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACH')"
            @click="attachmentInput?.click()"
          >
            <i class="i-lucide-paperclip mr-1 inline-block size-4" />
            {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACH') }}
          </button>
          <span v-if="selectedFiles.length" class="text-xs text-n-slate-10">
            {{
              t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACHMENT_COUNT', {
                count: selectedFiles.length,
                max: MAX_ATTACHMENTS,
              })
            }}
          </span>
        </div>
        <button
          type="submit"
          class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:cursor-not-allowed disabled:opacity-50"
          data-testid="kanban-opportunity-note-submit"
          :disabled="isSavingNote || !noteContent.trim()"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ADD_NOTE') }}
        </button>
      </div>
      <ul
        v-if="selectedFiles.length"
        class="flex flex-wrap gap-2"
        data-testid="kanban-opportunity-note-selected-files"
      >
        <li
          v-for="(file, index) in selectedFiles"
          :key="`${file.name}-${file.size}-${index}`"
          class="flex max-w-full items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-12"
        >
          <span class="max-w-48 truncate">{{ file.name }}</span>
          <button
            type="button"
            class="rounded-full p-0.5 hover:bg-n-alpha-3 focus:outline-none focus:ring-1 focus:ring-n-brand"
            :aria-label="file.name"
            @click="removeSelectedFile(index)"
          >
            <i class="i-lucide-x size-3" />
          </button>
        </li>
      </ul>
    </form>

    <p
      v-if="isLoading"
      data-testid="kanban-opportunity-timeline-loading"
      class="mb-0 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOADING') }}
    </p>

    <p
      v-else-if="loadError"
      data-testid="kanban-opportunity-timeline-load-error"
      class="mb-0 text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>

    <p
      v-else-if="timelineItems.length === 0"
      data-testid="kanban-opportunity-timeline-empty"
      class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EMPTY') }}
    </p>

    <ol
      v-else
      class="grid gap-5"
      data-testid="kanban-opportunity-timeline-list"
    >
      <li
        v-for="item in timelineItems"
        :key="`${item.itemType}-${item.id}`"
        :data-testid="
          item.itemType === 'event'
            ? 'kanban-opportunity-timeline-event'
            : 'kanban-opportunity-timeline-item'
        "
      >
        <article
          v-if="item.itemType === 'note'"
          class="group rounded-lg bg-n-alpha-1 p-3"
          data-testid="kanban-opportunity-timeline-note"
        >
          <div class="flex gap-3">
            <div class="flex size-8 flex-none items-center justify-center">
              <Avatar
                v-if="item.user"
                :name="item.user.name"
                :src="item.user.avatarUrl"
                :size="28"
                rounded-full
              />
              <span
                v-else
                class="flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
                :title="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')"
              >
                <i class="i-lucide-settings size-4" />
              </span>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-start justify-between gap-2">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{
                      item.user?.name ||
                      t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')
                    }}
                  </span>
                  <time class="text-xs text-n-slate-10">
                    {{ eventTimestamp(item) }}
                  </time>
                </div>
                <div
                  v-if="canManageNote(item) && editingNoteId !== item.id"
                  class="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100"
                >
                  <button
                    type="button"
                    class="rounded px-2 py-1 text-xs text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
                    @click="startEditingNote(item)"
                  >
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EDIT_NOTE') }}
                  </button>
                  <button
                    type="button"
                    class="rounded px-2 py-1 text-xs text-n-ruby-11 hover:bg-n-ruby-2 focus:outline-none focus:ring-1 focus:ring-n-ruby-8"
                    @click="requestDeleteNote(item)"
                  >
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.DELETE_NOTE') }}
                  </button>
                </div>
              </div>

              <textarea
                v-if="editingNoteId === item.id"
                v-model="editingContent"
                rows="3"
                class="mt-2 w-full resize-y rounded-md border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
              />
              <p
                v-else
                class="mb-0 mt-2 whitespace-pre-wrap break-words text-sm leading-5 text-n-slate-12"
              >
                {{ item.content }}
              </p>

              <div
                v-if="editingNoteId === item.id"
                class="mt-2 flex items-center gap-2"
              >
                <button
                  type="button"
                  class="rounded-md bg-n-brand px-2.5 py-1.5 text-xs font-medium text-white hover:bg-n-brand/90 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isSavingEdit || !editingContent.trim()"
                  @click="saveNoteEdit(item)"
                >
                  {{ t('KANBAN.OPPORTUNITY_DETAILS.SAVE') }}
                </button>
                <button
                  type="button"
                  class="rounded-md border border-n-weak px-2.5 py-1.5 text-xs text-n-slate-12 hover:bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-brand"
                  :disabled="isSavingEdit"
                  @click="cancelEditingNote"
                >
                  {{ t('KANBAN.OPPORTUNITY_DETAILS.CANCEL') }}
                </button>
              </div>

              <div
                v-if="item.attachments?.length"
                class="mt-3 flex flex-wrap gap-2"
              >
                <a
                  v-for="attachment in item.attachments"
                  :key="attachment.id"
                  :href="attachment.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="overflow-hidden rounded-md border border-n-weak bg-n-background text-xs text-n-slate-12 hover:border-n-brand"
                  :title="attachment.filename"
                >
                  <img
                    v-if="isImageAttachment(attachment)"
                    :src="attachment.url"
                    :alt="attachment.filename"
                    class="size-20 object-cover"
                  />
                  <span
                    v-else
                    class="flex max-w-52 items-center gap-2 px-2 py-2"
                  >
                    <i
                      class="i-lucide-file-text size-4 flex-none text-n-slate-10"
                    />
                    <span class="min-w-0 truncate">{{
                      attachment.filename
                    }}</span>
                    <span class="flex-none text-n-slate-10">
                      {{ formatFileSize(attachment.byteSize) }}
                    </span>
                  </span>
                </a>
              </div>
            </div>
          </div>
        </article>

        <div v-else class="flex gap-3">
          <div class="flex size-8 flex-none items-center justify-center">
            <Avatar
              v-if="item.user"
              :name="item.user.name"
              :src="item.user.avatarUrl"
              :size="28"
              rounded-full
            />
            <span
              v-else
              class="flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
              :title="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')"
            >
              <i class="i-lucide-settings size-4" />
            </span>
          </div>
          <div class="min-w-0 flex-1 border-b border-n-weak pb-4">
            <p class="mb-1 text-sm leading-5 text-n-slate-12">
              <span class="font-medium">
                {{
                  item.user?.name ||
                  t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')
                }}
              </span>
              {{ eventMessage(item) }}
            </p>
            <time class="text-xs text-n-slate-10">
              {{ eventTimestamp(item) }}
            </time>
          </div>
        </div>
      </li>
    </ol>

    <button
      v-if="hasMore && !loadError"
      type="button"
      class="mx-auto rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-50"
      data-testid="kanban-opportunity-timeline-load-more"
      :disabled="isLoadingMore"
      @click="loadEvents(true)"
    >
      {{
        isLoadingMore
          ? t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOADING')
          : t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_MORE')
      }}
    </button>
    <Dialog
      ref="deleteDialogRef"
      :title="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.DELETE_NOTE')"
      :description="
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.DELETE_NOTE_CONFIRM')
      "
      :cancel-button-label="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL')"
      :confirm-button-label="
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.DELETE_NOTE')
      "
      @confirm="confirmDeleteNote"
    />
  </section>
</template>
