import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';

const PAGE_LIMIT = 20;

// Events and notes are separate collections that only meet on screen, so each keeps its
// own cursor and the merged list is re-sorted whenever either side changes.
const SOURCES = [
  {
    itemType: 'event',
    request: (...args) => KanbanBoardsAPI.getCardEvents(...args),
  },
  {
    itemType: 'note',
    request: (...args) => KanbanBoardsAPI.getCardNotes(...args),
  },
];

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.message || fallback;

const camelize = data => camelcaseKeys(data || {}, { deep: true });

const asTimelineItem = (item, itemType) => ({ ...item, itemType });

const byRecency = (first, second) =>
  second.createdAt - first.createdAt || second.id - first.id;

const isNote = (item, note) => item.itemType === 'note' && item.id === note.id;

export function useCardTimeline(boardId, cardId) {
  const { t } = useI18n();

  const items = ref([]);
  const isLoading = ref(true);
  const isLoadingMore = ref(false);
  const loadError = ref('');
  const paging = ref(SOURCES.map(() => ({ hasMore: true, cursor: null })));

  const hasMore = computed(() => paging.value.some(source => source.hasMore));

  const setItems = nextItems => {
    items.value = [...nextItems].sort(byRecency);
  };

  const fetchPage = async (index, append) => {
    const { hasMore: sourceHasMore, cursor } = paging.value[index];
    if (append && !sourceHasMore) return { payload: [], hasMore: false };

    const params = { limit: PAGE_LIMIT };
    if (append && cursor) params.before_id = cursor;

    const response = await SOURCES[index].request(boardId, cardId, params);
    return camelize(response.data);
  };

  const load = async (append = false) => {
    if (append) isLoadingMore.value = true;
    else {
      isLoading.value = true;
      loadError.value = '';
    }

    try {
      const pages = await Promise.all(
        SOURCES.map((_source, index) => fetchPage(index, append))
      );
      const fetched = pages.flatMap((page, index) =>
        (page.payload || []).map(item =>
          asTimelineItem(item, SOURCES[index].itemType)
        )
      );

      paging.value = pages.map(page => ({
        hasMore: Boolean(page.hasMore),
        cursor: page.nextCursor,
      }));
      setItems(append ? [...items.value, ...fetched] : fetched);
    } catch (error) {
      loadError.value = getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_ERROR')
      );
      if (!append) useAlert(loadError.value);
    } finally {
      isLoading.value = false;
      isLoadingMore.value = false;
    }
  };

  // Note writes all report the same way: the caller only needs to know whether it may
  // clear its editor.
  const runNoteWrite = async write => {
    try {
      await write();
      return true;
    } catch (error) {
      useAlert(
        getErrorMessage(
          error,
          t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_ERROR')
        )
      );
      return false;
    }
  };

  const createNote = ({ content, files }) =>
    runNoteWrite(async () => {
      const payload = new FormData();
      payload.append('note[content]', content);
      files.forEach(file => payload.append('note[attachments][]', file));

      const response = await KanbanBoardsAPI.createCardNote(
        boardId,
        cardId,
        payload
      );
      setItems([
        asTimelineItem(camelize(response.data), 'note'),
        ...items.value,
      ]);
      useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_SAVED'));
    });

  const updateNote = (note, content) =>
    runNoteWrite(async () => {
      const response = await KanbanBoardsAPI.updateCardNote(
        boardId,
        cardId,
        note.id,
        { content }
      );
      const updated = asTimelineItem(camelize(response.data), 'note');
      setItems(items.value.map(item => (isNote(item, note) ? updated : item)));
    });

  const deleteNote = note =>
    runNoteWrite(async () => {
      await KanbanBoardsAPI.deleteCardNote(boardId, cardId, note.id);
      items.value = items.value.filter(item => !isNote(item, note));
    });

  return {
    items,
    isLoading,
    isLoadingMore,
    loadError,
    hasMore,
    load,
    createNote,
    updateNote,
    deleteNote,
  };
}
