<script setup>
import { useI18n } from 'vue-i18n';

import Editor from 'dashboard/components-next/Editor/Editor.vue';

const props = defineProps({
  description: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:description']);

const { t } = useI18n();
</script>

<template>
  <section class="grid min-w-0 content-start gap-4">
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
