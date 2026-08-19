<script setup>
import { useI18n } from 'vue-i18n';

import Editor from 'dashboard/components-next/Editor/Editor.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import KanbanPriorityDropdown from '../../KanbanPriorityDropdown.vue';

const props = defineProps({
  subject: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  priority: {
    type: String,
    default: '',
  },
  subjectError: {
    type: String,
    default: '',
  },
});

const emit = defineEmits([
  'update:subject',
  'update:description',
  'update:priority',
  'clearSubjectError',
]);

const { t } = useI18n();
</script>

<template>
  <section class="grid min-w-0 content-start gap-4">
    <NextInput
      :model-value="props.subject"
      data-testid="kanban-opportunity-subject"
      class="w-full"
      :label="t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE')"
      :message="props.subjectError"
      :message-type="props.subjectError ? 'error' : 'info'"
      @update:model-value="emit('update:subject', $event)"
      @input="emit('clearSubjectError')"
    />

    <slot name="after-subject" />

    <section class="grid gap-2 rounded-lg border border-n-weak p-3">
      <h3 class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY') }}
      </h3>
      <KanbanPriorityDropdown
        :model-value="props.priority"
        test-id="kanban-opportunity-priority"
        :none-label="t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY_NONE')"
        @update:model-value="emit('update:priority', $event)"
      />
    </section>

    <div class="grid min-w-0 gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.FIELD_SUMMARY') }}
      </span>
      <Editor
        :model-value="props.description"
        data-testid="kanban-opportunity-description"
        :show-character-count="false"
        :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.DESCRIPTION_PLACEHOLDER')"
        class="max-w-full w-full [&>div]:min-h-[6rem]"
        @update:model-value="emit('update:description', $event)"
      />
    </div>
  </section>
</template>
