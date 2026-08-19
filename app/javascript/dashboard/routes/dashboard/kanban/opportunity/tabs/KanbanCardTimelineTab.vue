<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useCardTimeline } from '../composables/useCardTimeline';
import KanbanNoteComposer from '../timeline/KanbanNoteComposer.vue';
import KanbanTimelineEvent from '../timeline/KanbanTimelineEvent.vue';
import KanbanTimelineNote from '../timeline/KanbanTimelineNote.vue';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
  cardId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');

const {
  items,
  isLoading,
  isLoadingMore,
  loadError,
  hasMore,
  load,
  createNote,
  updateNote,
  deleteNote,
} = useCardTimeline(props.boardId, props.cardId);

const deleteDialogRef = ref(null);
const notePendingDeletion = ref(null);

const canManageNote = note =>
  isAdmin.value || note.user?.id === currentUser.value?.id;

const requestDeleteNote = note => {
  notePendingDeletion.value = note;
  deleteDialogRef.value?.open();
};

const confirmDeleteNote = async () => {
  await deleteNote(notePendingDeletion.value);
  notePendingDeletion.value = null;
  deleteDialogRef.value?.close();
};

onMounted(() => load());
</script>

<template>
  <section
    data-testid="kanban-opportunity-timeline-tab"
    class="grid min-w-0 gap-4"
  >
    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.TAB_TITLE') }}
    </h3>

    <KanbanNoteComposer :save-note="createNote" />

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
      v-else-if="items.length === 0"
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
        v-for="item in items"
        :key="`${item.itemType}-${item.id}`"
        :data-testid="
          item.itemType === 'event'
            ? 'kanban-opportunity-timeline-event'
            : 'kanban-opportunity-timeline-item'
        "
      >
        <KanbanTimelineNote
          v-if="item.itemType === 'note'"
          :note="item"
          :can-manage="canManageNote(item)"
          :update-note="updateNote"
          @request-delete="requestDeleteNote"
        />
        <KanbanTimelineEvent v-else :event="item" />
      </li>
    </ol>

    <button
      v-if="hasMore && !loadError"
      type="button"
      class="mx-auto rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 disabled:cursor-not-allowed disabled:opacity-50"
      data-testid="kanban-opportunity-timeline-load-more"
      :disabled="isLoadingMore"
      @click="load(true)"
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
