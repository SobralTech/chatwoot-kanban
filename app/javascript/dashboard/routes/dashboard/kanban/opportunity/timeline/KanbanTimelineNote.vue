<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import { formatBytes } from 'shared/helpers/FileHelper';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import KanbanTimelineAvatar from './KanbanTimelineAvatar.vue';

const props = defineProps({
  note: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  // Resolves to whether the edit was stored, so the note knows when to leave edit mode.
  updateNote: { type: Function, required: true },
});

const emit = defineEmits(['requestDelete']);

const { t } = useI18n();

const isEditing = ref(false);
const draft = ref('');
const isSaving = ref(false);

const authorName = computed(
  () =>
    props.note.user?.name ||
    t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')
);

const timestamp = computed(() =>
  shortTimestamp(dynamicTime(props.note.createdAt), true)
);

const isImage = attachment => attachment.contentType?.startsWith('image/');

const startEditing = () => {
  draft.value = props.note.content;
  isEditing.value = true;
};

const cancelEditing = () => {
  isEditing.value = false;
  draft.value = '';
};

const saveEdit = async () => {
  if (!draft.value.trim() || isSaving.value) return;

  isSaving.value = true;
  const saved = await props.updateNote(props.note, draft.value);
  isSaving.value = false;

  if (saved) cancelEditing();
};
</script>

<template>
  <article
    class="group rounded-lg bg-n-alpha-1 p-3"
    data-testid="kanban-opportunity-timeline-note"
  >
    <div class="flex gap-3">
      <KanbanTimelineAvatar :user="note.user" />
      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ authorName }}
            </span>
            <time class="text-xs text-n-slate-10">{{ timestamp }}</time>
          </div>
          <div
            v-if="canManage && !isEditing"
            class="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100"
          >
            <NextButton
              type="button"
              ghost
              slate
              xs
              :label="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.EDIT_NOTE')"
              @click="startEditing"
            />
            <NextButton
              type="button"
              ghost
              ruby
              xs
              :label="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.DELETE_NOTE')"
              @click="emit('requestDelete', note)"
            />
          </div>
        </div>

        <template v-if="isEditing">
          <textarea
            v-model="draft"
            rows="3"
            class="mb-0 mt-2 block w-full resize-y rounded-lg border-none bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand"
          />
          <div class="mt-2 flex items-center gap-2">
            <NextButton
              type="button"
              sm
              :label="t('KANBAN.OPPORTUNITY_DETAILS.SAVE')"
              :is-loading="isSaving"
              :disabled="isSaving || !draft.trim()"
              @click="saveEdit"
            />
            <NextButton
              type="button"
              outline
              slate
              sm
              :label="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL')"
              :disabled="isSaving"
              @click="cancelEditing"
            />
          </div>
        </template>
        <p
          v-else
          class="mb-0 mt-2 whitespace-pre-wrap break-words text-sm leading-5 text-n-slate-12"
        >
          {{ note.content }}
        </p>

        <div v-if="note.attachments?.length" class="mt-3 flex flex-wrap gap-2">
          <a
            v-for="attachment in note.attachments"
            :key="attachment.id"
            :href="attachment.url"
            target="_blank"
            rel="noopener noreferrer"
            class="overflow-hidden rounded-md border border-n-weak bg-n-background text-xs text-n-slate-12 hover:border-n-brand"
            :title="attachment.filename"
          >
            <img
              v-if="isImage(attachment)"
              :src="attachment.url"
              :alt="attachment.filename"
              class="size-20 object-cover"
            />
            <span v-else class="flex max-w-52 items-center gap-2 px-2 py-2">
              <i class="i-lucide-file-text size-4 flex-none text-n-slate-10" />
              <span class="min-w-0 truncate">{{ attachment.filename }}</span>
              <span class="flex-none text-n-slate-10">
                {{ formatBytes(attachment.byteSize, 0) }}
              </span>
            </span>
          </a>
        </div>
      </div>
    </div>
  </article>
</template>
