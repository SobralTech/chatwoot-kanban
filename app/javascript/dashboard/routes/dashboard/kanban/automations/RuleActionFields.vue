<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Select from 'dashboard/components-next/select/Select.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { actionSchema } from './ruleActionSchema';

defineProps({
  stages: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  reasons: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
  variables: { type: Array, default: () => [] },
});

const action = defineModel('action', { type: Object, required: true });

const { t } = useI18n();

const field = computed(() => actionSchema(action.value.action_name)?.field);

const assignModes = computed(() =>
  ['SET', 'ADD', 'ROUND_ROBIN'].map(mode => ({
    value: mode.toLowerCase(),
    label: t(`KANBAN.AUTOMATIONS.FORM.ASSIGN_MODES.${mode}`),
  }))
);

const sampleValues = computed(() => ({
  contact_name: t('KANBAN.AUTOMATIONS.FORM.PREVIEW_SAMPLE.CONTACT_NAME'),
  agent_name: t('KANBAN.AUTOMATIONS.FORM.PREVIEW_SAMPLE.AGENT_NAME'),
  card_subject: t('KANBAN.AUTOMATIONS.FORM.PREVIEW_SAMPLE.CARD_SUBJECT'),
  total: t('KANBAN.AUTOMATIONS.FORM.PREVIEW_SAMPLE.TOTAL'),
  'card.stage.name': t('KANBAN.AUTOMATIONS.FORM.PREVIEW_SAMPLE.STAGE'),
}));

// A rough stand-in for the Liquid rendering the backend does; it only fills the
// variables the picker offers and leaves anything else alone.
const renderedPreview = computed(() =>
  String(action.value.action_params?.content || '').replace(
    /{{\s*([^}]+?)\s*}}/g,
    (_match, key) => sampleValues.value[key.trim()] || `{{${key.trim()}}}`
  )
);

const appendVariable = key => {
  const params = action.value.action_params;
  params.content = `${params.content || ''}{{${key}}}`;
};
</script>

<template>
  <Select
    v-if="field === 'stage'"
    v-model="action.action_params.stage_id"
    :options="stages"
    :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_STAGE')"
    full-width
  />

  <div v-else-if="field === 'agents'" class="grid gap-3">
    <TagMultiSelectComboBox
      v-model="action.action_params.agent_ids"
      :options="agents"
      :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_AGENTS')"
      :search-placeholder="t('KANBAN.AUTOMATIONS.FORM.SEARCH_AGENTS')"
      :empty-state="t('KANBAN.AUTOMATIONS.FORM.NO_AGENTS')"
    />
    <Select
      v-model="action.action_params.mode"
      :options="assignModes"
      full-width
    />
  </div>

  <Select
    v-else-if="field === 'priority'"
    v-model="action.action_params.priority"
    :options="priorities"
    :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_PRIORITY')"
    full-width
  />

  <TagMultiSelectComboBox
    v-else-if="field === 'labels'"
    v-model="action.action_params.labels"
    :options="labels"
    :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_LABELS')"
    :search-placeholder="t('KANBAN.AUTOMATIONS.FORM.SEARCH_LABELS')"
    :empty-state="t('KANBAN.AUTOMATIONS.FORM.NO_LABELS')"
  />

  <div v-else-if="field === 'message'" class="grid gap-3">
    <div class="grid gap-2 lg:grid-cols-[minmax(0,1fr)_13rem]">
      <textarea
        v-model="action.action_params.content"
        rows="4"
        :placeholder="t('KANBAN.AUTOMATIONS.FORM.MESSAGE_PLACEHOLDER')"
        class="min-w-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm outline-none placeholder:text-n-slate-10 focus:border-n-brand"
      />
      <div class="grid content-start gap-2 rounded-md bg-n-alpha-2 p-2">
        <p class="text-xs font-medium text-n-slate-11">
          {{ t('KANBAN.AUTOMATIONS.FORM.VARIABLES') }}
        </p>
        <button
          v-for="variable in variables"
          :key="variable.key"
          type="button"
          class="truncate rounded px-2 py-1 text-left text-xs text-n-blue-11 hover:bg-n-alpha-2"
          @click="appendVariable(variable.key)"
        >
          {{ variable.label }}
        </button>
      </div>
    </div>
    <div class="rounded-md border border-n-weak bg-n-surface-2 p-3">
      <p class="mb-1 text-xs font-medium text-n-slate-11">
        {{ t('KANBAN.AUTOMATIONS.FORM.PREVIEW') }}
      </p>
      <p class="whitespace-pre-wrap text-sm text-n-slate-12">
        {{ renderedPreview || t('KANBAN.AUTOMATIONS.FORM.EMPTY_MESSAGE') }}
      </p>
    </div>
  </div>

  <div v-else-if="field === 'dueAt'" class="grid gap-3">
    <label class="grid gap-1 text-sm text-n-slate-12">
      {{ t('KANBAN.AUTOMATIONS.FORM.DAYS') }}
      <input
        v-model="action.action_params.days"
        type="number"
        min="1"
        class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 outline-none focus:border-n-brand"
      />
    </label>
    <label class="flex items-center gap-2 text-sm text-n-slate-12">
      <input v-model="action.action_params.business_days" type="checkbox" />
      {{ t('KANBAN.AUTOMATIONS.FORM.BUSINESS_DAYS') }}
    </label>
  </div>

  <Select
    v-else-if="field === 'reason'"
    v-model="action.action_params.reason_id"
    :options="reasons"
    :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_REASON')"
    full-width
  />
</template>
