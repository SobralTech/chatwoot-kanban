<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  templates: {
    type: Array,
    default: () => [],
  },
  isCreating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select']);
const { t } = useI18n();
const stageSeparator = '›';

const previewStages = template => (template.stages || []).slice(0, 3);
const extraStagesCount = template =>
  Math.max((template.stages || []).length - 3, 0);

const selectTemplate = key => {
  if (!props.isCreating) emit('select', key);
};
</script>

<template>
  <section
    data-testid="kanban-board-template-picker"
    class="mx-auto grid w-full max-w-4xl gap-6 p-6"
  >
    <div class="grid gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('KANBAN.BOARD_TEMPLATES.TITLE') }}
      </h1>
    </div>

    <div
      v-if="!templates.length"
      data-testid="kanban-board-template-picker-loading"
      class="rounded-lg border border-dashed border-n-weak px-4 py-8 text-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD_EDIT.LOADING') }}
    </div>

    <div v-else class="grid gap-4 sm:grid-cols-2">
      <button
        v-for="template in templates"
        :key="template.key"
        :data-testid="`kanban-board-template-${template.key}`"
        type="button"
        class="group flex min-h-52 w-full flex-col gap-4 rounded-lg border border-n-weak bg-n-surface-2 p-5 text-left transition-colors hover:border-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isCreating"
        @click="selectTemplate(template.key)"
      >
        <div class="grid gap-1">
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ template.name }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ template.description }}
          </p>
        </div>

        <div
          class="flex min-h-12 flex-wrap content-start items-center gap-x-1 gap-y-2 text-sm text-n-slate-11"
        >
          <template
            v-for="(stage, index) in previewStages(template)"
            :key="stage"
          >
            <span>{{ stage }}</span>
            <template v-if="index < previewStages(template).length - 1">
              <span aria-hidden="true">{{ stageSeparator }}</span>
            </template>
          </template>
          <span
            v-if="extraStagesCount(template)"
            class="font-medium text-n-slate-12"
          >
            {{
              t('KANBAN.BOARD_TEMPLATES.STAGES_MORE', {
                count: extraStagesCount(template),
              })
            }}
          </span>
        </div>

        <div class="mt-auto flex flex-wrap items-center gap-2">
          <span
            class="rounded-full bg-n-teal-2 px-2 py-1 text-xs font-medium text-n-teal-11"
          >
            {{ template.wonStageName }}
          </span>
          <span
            class="rounded-full bg-n-ruby-2 px-2 py-1 text-xs font-medium text-n-ruby-11"
          >
            {{ template.lostStageName }}
          </span>
        </div>

        <div
          v-if="template.lostReasonsCount || template.customFieldsCount"
          class="flex flex-wrap gap-x-3 gap-y-1 text-xs text-n-slate-10"
        >
          <span v-if="template.lostReasonsCount">
            {{
              t('KANBAN.BOARD_TEMPLATES.REASONS_COUNT', {
                count: template.lostReasonsCount,
              })
            }}
          </span>
          <span v-if="template.customFieldsCount">
            {{
              t('KANBAN.BOARD_TEMPLATES.FIELDS_COUNT', {
                count: template.customFieldsCount,
              })
            }}
          </span>
        </div>
      </button>
    </div>

    <p
      v-if="isCreating"
      data-testid="kanban-board-template-picker-creating"
      class="text-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD_TEMPLATES.CREATING') }}
    </p>
    <p v-else class="text-center text-sm text-n-slate-10">
      {{ t('KANBAN.BOARD_TEMPLATES.SUBTITLE') }}
    </p>
  </section>
</template>
