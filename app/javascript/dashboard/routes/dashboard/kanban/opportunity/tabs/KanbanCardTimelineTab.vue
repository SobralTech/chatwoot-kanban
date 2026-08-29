<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
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
      class="grid list-none gap-5 ps-0"
      data-testid="kanban-opportunity-timeline-list"
    >
      <li
        v-for="item in items"
        :key="`${item.itemType}-${item.id}`"
        class="group/timeline"
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
        <KanbanTimelineEvent v-else :event="item" :board-id="boardId" />
      </li>
    </ol>

    <NextButton
      v-if="hasMore && !loadError"
      type="button"
      outline
      slate
      sm
      class="mx-auto"
      data-testid="kanban-opportunity-timeline-load-more"
      :is-loading="isLoadingMore"
      :label="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.LOAD_MORE')"
      @click="load(true)"
    />

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
