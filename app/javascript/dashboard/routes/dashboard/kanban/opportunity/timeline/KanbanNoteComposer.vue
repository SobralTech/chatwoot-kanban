<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';

const props = defineProps({
  // Resolves to whether the note was stored, so the composer knows when to clear itself.
  saveNote: { type: Function, required: true },
});

const { t } = useI18n();

const MAX_ATTACHMENTS = 5;
const MAX_ATTACHMENT_SIZE = 20 * 1024 * 1024;

const content = ref('');
const files = ref([]);
const fileInput = ref(null);
const isSaving = ref(false);

const addFiles = event => {
  const picked = Array.from(event.target.files || []);
  const withinSizeLimit = picked.filter(
    file => file.size <= MAX_ATTACHMENT_SIZE
  );

  if (withinSizeLimit.length !== picked.length) {
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACHMENT_TOO_LARGE'));
  }

  const availableSlots = MAX_ATTACHMENTS - files.value.length;
  if (withinSizeLimit.length > availableSlots) {
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.TOO_MANY_ATTACHMENTS'));
  }

  files.value = [
    ...files.value,
    ...withinSizeLimit.slice(0, Math.max(availableSlots, 0)),
  ];
  event.target.value = '';
};

const removeFile = index => {
  files.value = files.value.filter((_file, fileIndex) => fileIndex !== index);
};

const submit = async () => {
  if (!content.value.trim() || isSaving.value) return;

  isSaving.value = true;
  const saved = await props.saveNote({
    content: content.value,
    files: files.value,
  });
  isSaving.value = false;

  if (!saved) return;

  content.value = '';
  files.value = [];
};
</script>

<template>
  <form
    class="grid gap-3 rounded-lg border border-n-weak p-3"
    data-testid="kanban-opportunity-note-form"
    @submit.prevent="submit"
  >
    <textarea
      v-model="content"
      rows="3"
      class="w-full resize-y rounded-md border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
      :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.NOTE_PLACEHOLDER')"
      data-testid="kanban-opportunity-note-input"
    />
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <input
          ref="fileInput"
          type="file"
          multiple
          class="hidden"
          @change="addFiles"
        />
        <button
          type="button"
          class="rounded-md border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1 focus:outline-none focus:ring-1 focus:ring-n-brand"
          data-testid="kanban-opportunity-note-attach"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACH')"
          @click="fileInput?.click()"
        >
          <i class="i-lucide-paperclip mr-1 inline-block size-4" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACH') }}
        </button>
        <span v-if="files.length" class="text-xs text-n-slate-10">
          {{
            t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ATTACHMENT_COUNT', {
              count: files.length,
              max: MAX_ATTACHMENTS,
            })
          }}
        </span>
      </div>
      <button
        type="submit"
        class="rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white hover:bg-n-brand/90 disabled:cursor-not-allowed disabled:opacity-50"
        data-testid="kanban-opportunity-note-submit"
        :disabled="isSaving || !content.trim()"
      >
        {{ t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.ADD_NOTE') }}
      </button>
    </div>
    <ul
      v-if="files.length"
      class="flex flex-wrap gap-2"
      data-testid="kanban-opportunity-note-selected-files"
    >
      <li
        v-for="(file, index) in files"
        :key="`${file.name}-${file.size}-${index}`"
        class="flex max-w-full items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-12"
      >
        <span class="max-w-48 truncate">{{ file.name }}</span>
        <button
          type="button"
          class="rounded-full p-0.5 hover:bg-n-alpha-3 focus:outline-none focus:ring-1 focus:ring-n-brand"
          :aria-label="file.name"
          @click="removeFile(index)"
        >
          <i class="i-lucide-x size-3" />
        </button>
      </li>
    </ul>
  </form>
</template>
