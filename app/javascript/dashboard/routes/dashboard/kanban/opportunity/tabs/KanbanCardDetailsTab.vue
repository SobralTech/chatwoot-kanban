<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Editor from 'dashboard/components-next/Editor/Editor.vue';
import KanbanCardAdditionalDataTab from '../../KanbanCardAdditionalDataTab.vue';

const props = defineProps({
  description: {
    type: String,
    default: '',
  },
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
  customFields: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:description']);

const { t } = useI18n();
const additionalDataTabRef = ref(null);
const hasUnsavedChanges = computed(
  () => !!additionalDataTabRef.value?.hasUnsavedChanges
);
const saveFieldValues = () =>
  additionalDataTabRef.value?.saveFieldValues() ?? true;

defineExpose({ hasUnsavedChanges, saveFieldValues });
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

    <KanbanCardAdditionalDataTab
      v-if="props.customFields.length"
      ref="additionalDataTabRef"
      :board-id="props.boardId"
      :card-id="props.cardId"
      :custom-fields="props.customFields"
      class="border-t border-n-weak pt-5"
    />
  </section>
</template>
