<script setup>
import { computed } from 'vue';
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

defineEmits(['select']);
const { t } = useI18n();

const PREVIEW_STAGE_LIMIT = 3;

const templateCards = computed(() =>
  props.templates.map(template => ({
    ...template,
    stagesPreview: template.stages.slice(0, PREVIEW_STAGE_LIMIT).join(' › '),
    extraStagesCount: Math.max(template.stages.length - PREVIEW_STAGE_LIMIT, 0),
  }))
);
</script>

<template>
  <section
    data-testid="kanban-board-template-picker"
    class="mx-auto grid w-full max-w-4xl gap-6 p-6"
  >
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('KANBAN.BOARD_TEMPLATES.TITLE') }}
    </h1>

    <div class="grid gap-4 sm:grid-cols-2">
      <button
        v-for="template in templateCards"
        :key="template.key"
        :data-testid="`kanban-board-template-${template.key}`"
        type="button"
        class="group flex min-h-52 w-full flex-col gap-4 rounded-lg border border-n-weak bg-n-surface-2 p-5 text-left transition-colors hover:border-n-brand focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isCreating"
        @click="$emit('select', template.key)"
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
          <span>{{ template.stagesPreview }}</span>
          <span
            v-if="template.extraStagesCount"
            class="font-medium text-n-slate-12"
          >
            {{
              t('KANBAN.OVERVIEW.EXTRA_COUNT', {
                count: template.extraStagesCount,
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
