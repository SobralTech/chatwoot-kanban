<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import {
  ENTRY_RULE_FIELDS,
  NONE_VALUE,
  buildConditions,
  conditionsToForm,
  emptyConditionForm,
  isRuleWiderThan,
} from 'dashboard/helper/kanbanEntryRules';

const props = defineProps({
  boardId: { type: [Number, String], required: true },
  stages: { type: Array, default: () => [] },
});

const RULE_STATUS = {
  ALL: 'all',
  ACTIVE: 'active',
  INACTIVE: 'inactive',
};

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getAllInboxes');
const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');
const labels = useMapGetter('labels/getLabels');

const isLoading = ref(false);
const loadError = ref('');
const rules = ref([]);
const ruleSearch = ref('');
const ruleStatus = ref(RULE_STATUS.ALL);
const showFormModal = ref(false);
const editingRuleId = ref(null);
const isSaving = ref(false);
const formError = ref('');
const showRemoveConfirmation = ref(false);
const rulePendingRemoval = ref(null);
const isRemoving = ref(false);
const saveConfirmation = ref(null);
const importPrompt = ref(null);
const isImporting = ref(false);

const form = reactive({
  name: '',
  allInboxes: true,
  inboxIds: [],
  kanbanStageId: '',
  conditions: emptyConditionForm(),
});

const noneOption = computed(() => ({
  value: NONE_VALUE,
  label: t('KANBAN.ENTRY_RULES.NONE_OPTION'),
}));

const fieldLabels = computed(() => ({
  labels: t('KANBAN.ENTRY_RULES.FIELDS.LABELS'),
  assignee_id: t('KANBAN.ENTRY_RULES.FIELDS.ASSIGNEE_ID'),
  team_id: t('KANBAN.ENTRY_RULES.FIELDS.TEAM_ID'),
  priority: t('KANBAN.ENTRY_RULES.FIELDS.PRIORITY'),
}));

const operatorLabels = computed(() => ({
  is_one_of: t('KANBAN.ENTRY_RULES.OPERATORS.IS_ONE_OF'),
  is_not_one_of: t('KANBAN.ENTRY_RULES.OPERATORS.IS_NOT_ONE_OF'),
  includes_any: t('KANBAN.ENTRY_RULES.OPERATORS.INCLUDES_ANY'),
  includes_all: t('KANBAN.ENTRY_RULES.OPERATORS.INCLUDES_ALL'),
  not_includes: t('KANBAN.ENTRY_RULES.OPERATORS.NOT_INCLUDES'),
}));

const toOptions = (items, labelKey = 'name') =>
  items.map(item => ({ value: String(item.id), label: item[labelKey] }));

const inboxOptions = computed(() => toOptions(inboxes.value));

const ruleStatusOptions = computed(() => [
  {
    value: RULE_STATUS.ALL,
    label: t('KANBAN.ENTRY_RULES.STATUS_ALL'),
  },
  {
    value: RULE_STATUS.ACTIVE,
    label: t('KANBAN.ENTRY_RULES.STATUS_ACTIVE'),
  },
  {
    value: RULE_STATUS.INACTIVE,
    label: t('KANBAN.ENTRY_RULES.STATUS_INACTIVE'),
  },
]);

const isFilteringRules = computed(
  () => Boolean(ruleSearch.value.trim()) || ruleStatus.value !== RULE_STATUS.ALL
);

const filteredRules = computed(() => {
  const search = ruleSearch.value.trim().toLowerCase();
  if (!search && ruleStatus.value === RULE_STATUS.ALL) return rules.value;

  return rules.value.filter(rule => {
    const matchesName = !search || rule.name.toLowerCase().includes(search);
    const matchesStatus =
      ruleStatus.value === RULE_STATUS.ALL ||
      (ruleStatus.value === RULE_STATUS.ACTIVE && rule.active) ||
      (ruleStatus.value === RULE_STATUS.INACTIVE && !rule.active);

    return matchesName && matchesStatus;
  });
});

const valueOptionsByField = computed(() => ({
  labels: [
    noneOption.value,
    ...labels.value.map(label => ({ value: label.title, label: label.title })),
  ],
  assignee_id: [noneOption.value, ...toOptions(agents.value)],
  team_id: [noneOption.value, ...toOptions(teams.value)],
  priority: [
    noneOption.value,
    { value: 'low', label: t('KANBAN.ENTRY_RULES.PRIORITY.LOW') },
    { value: 'medium', label: t('KANBAN.ENTRY_RULES.PRIORITY.MEDIUM') },
    { value: 'high', label: t('KANBAN.ENTRY_RULES.PRIORITY.HIGH') },
    { value: 'urgent', label: t('KANBAN.ENTRY_RULES.PRIORITY.URGENT') },
  ],
}));

const valueLabelsByField = computed(() =>
  Object.fromEntries(
    Object.entries(valueOptionsByField.value).map(([attributeKey, options]) => [
      attributeKey,
      new Map(options.map(option => [String(option.value), option.label])),
    ])
  )
);

const operatorOptionsByField = computed(() =>
  Object.fromEntries(
    ENTRY_RULE_FIELDS.map(field => [
      field.key,
      field.operators.map(operator => ({
        value: operator,
        label: operatorLabels.value[operator],
      })),
    ])
  )
);

const stageOptions = computed(() => [
  { value: '', label: t('KANBAN.ENTRY_RULES.FIRST_STAGE') },
  ...toOptions(props.stages),
]);

const inboxNameById = computed(
  () => new Map(inboxes.value.map(inbox => [inbox.id, inbox.name]))
);

const ruleInboxSummary = rule => {
  if (rule.allInboxes) return t('KANBAN.ENTRY_RULES.ALL_INBOXES');
  const names = (rule.inboxIds || []).map(
    id => inboxNameById.value.get(id) || `#${id}`
  );
  return names.length ? names.join(', ') : t('KANBAN.ENTRY_RULES.NO_INBOX');
};

const ruleConditionSummary = rule => {
  if (!rule.conditions?.length) {
    return t('KANBAN.ENTRY_RULES.NO_CONDITIONS');
  }

  return rule.conditions
    .map(condition => {
      const values = condition.values
        .map(
          value =>
            valueLabelsByField.value[condition.attributeKey].get(
              String(value)
            ) ?? String(value)
        )
        .join(', ');

      return t('KANBAN.ENTRY_RULES.CONDITION_SUMMARY', {
        field: fieldLabels.value[condition.attributeKey],
        operator: operatorLabels.value[condition.filterOperator],
        values,
      });
    })
    .join(' · ');
};

const fetchRules = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getEntryRules(props.boardId);
    rules.value = camelcaseKeys(response.data || [], { deep: true });
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.ENTRY_RULES.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const resetForm = () => {
  form.name = '';
  form.allInboxes = true;
  form.inboxIds = [];
  form.kanbanStageId = '';
  form.conditions = emptyConditionForm();
  formError.value = '';
};

const openAddRuleModal = () => {
  resetForm();
  editingRuleId.value = null;
  showFormModal.value = true;
};

const openEditRuleModal = rule => {
  editingRuleId.value = rule.id;
  form.name = rule.name;
  form.allInboxes = rule.allInboxes;
  form.inboxIds = [...(rule.inboxIds || [])];
  form.kanbanStageId = rule.kanbanStageId || '';
  form.conditions = conditionsToForm(rule.conditions);
  formError.value = '';
  showFormModal.value = true;
};

const payloadFromForm = () => ({
  entry_rule: {
    name: form.name,
    all_inboxes: form.allInboxes,
    inbox_ids: form.allInboxes ? [] : form.inboxIds,
    kanban_stage_id: form.kanbanStageId || null,
    conditions: buildConditions(form.conditions),
  },
});

const draftRuleFromForm = () => ({
  allInboxes: form.allInboxes,
  inboxIds: form.allInboxes ? [] : form.inboxIds,
  conditions: buildConditions(form.conditions),
});

const previewMatchingCount = async () => {
  isSaving.value = true;
  formError.value = '';
  try {
    const response = await KanbanBoardsAPI.previewEntryRule(
      props.boardId,
      payloadFromForm()
    );
    return response.data?.count || 0;
  } catch (error) {
    formError.value = apiErrorMessage(
      error,
      t('KANBAN.ENTRY_RULES.PREVIEW_ERROR')
    );
    return null;
  } finally {
    isSaving.value = false;
  }
};

const persistRule = async (matchingCount = 0) => {
  isSaving.value = true;
  formError.value = '';

  try {
    const response = editingRuleId.value
      ? await KanbanBoardsAPI.updateEntryRule(
          props.boardId,
          editingRuleId.value,
          payloadFromForm()
        )
      : await KanbanBoardsAPI.createEntryRule(props.boardId, payloadFromForm());

    const savedRule = camelcaseKeys(response.data, { deep: true });
    showFormModal.value = false;
    await fetchRules();
    if (matchingCount > 0) {
      importPrompt.value = { rule: savedRule, count: matchingCount };
    }
    useAlert(t('KANBAN.ENTRY_RULES.SAVE_SUCCESS'));
  } catch (error) {
    showFormModal.value = true;
    formError.value = apiErrorMessage(
      error,
      t('KANBAN.ENTRY_RULES.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const saveRule = async () => {
  if (!form.name.trim()) {
    formError.value = t('KANBAN.ENTRY_RULES.NAME_REQUIRED');
    return;
  }
  if (!form.allInboxes && !form.inboxIds.length) {
    formError.value = t('KANBAN.ENTRY_RULES.INBOX_REQUIRED');
    return;
  }

  const previousRule = rules.value.find(
    rule => rule.id === editingRuleId.value
  );
  if (previousRule && !isRuleWiderThan(draftRuleFromForm(), previousRule)) {
    await persistRule();
    return;
  }

  const matchingCount = await previewMatchingCount();
  if (matchingCount === null) return;
  if (matchingCount === 0) {
    await persistRule();
    return;
  }

  saveConfirmation.value = { count: matchingCount };
  showFormModal.value = false;
};

const cancelSaveConfirmation = () => {
  saveConfirmation.value = null;
  showFormModal.value = true;
};

const confirmSaveRule = async () => {
  const matchingCount = saveConfirmation.value.count;
  saveConfirmation.value = null;
  await persistRule(matchingCount);
};

const toggleRule = async rule => {
  try {
    await KanbanBoardsAPI.toggleEntryRule(props.boardId, rule.id, !rule.active);
    await fetchRules();
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ENTRY_RULES.SAVE_ERROR')));
  }
};

const openRemoveConfirmation = rule => {
  rulePendingRemoval.value = rule;
  showRemoveConfirmation.value = true;
};

const removeRule = async () => {
  isRemoving.value = true;
  try {
    await KanbanBoardsAPI.deleteEntryRule(
      props.boardId,
      rulePendingRemoval.value.id
    );
    showRemoveConfirmation.value = false;
    rulePendingRemoval.value = null;
    await fetchRules();
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ENTRY_RULES.REMOVE_ERROR')));
  } finally {
    isRemoving.value = false;
  }
};

// Order decides which rule wins when several match, so it is persisted on every drop.
const persistOrder = async () => {
  try {
    await KanbanBoardsAPI.reorderEntryRules(
      props.boardId,
      rules.value.map(rule => rule.id)
    );
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ENTRY_RULES.SAVE_ERROR')));
    await fetchRules();
  }
};

const runRetroactiveImport = async () => {
  isImporting.value = true;
  try {
    await KanbanBoardsAPI.importExistingConversations(props.boardId, {
      entry_rule_id: importPrompt.value.rule.id,
    });
    useAlert(t('KANBAN.ENTRY_RULES.IMPORT_STARTED'));
    importPrompt.value = null;
  } catch (error) {
    useAlert(apiErrorMessage(error, t('KANBAN.ENTRY_RULES.IMPORT_ERROR')));
  } finally {
    isImporting.value = false;
  }
};

onMounted(fetchRules);
</script>

<template>
  <div class="grid gap-4">
    <header class="flex items-center justify-between gap-3">
      <div>
        <h2 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('KANBAN.ENTRY_RULES.TITLE') }}
        </h2>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('KANBAN.ENTRY_RULES.DESCRIPTION') }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        size="sm"
        data-testid="kanban-entry-rule-add"
        :label="t('KANBAN.ENTRY_RULES.ADD_RULE')"
        @click="openAddRuleModal"
      />
    </header>

    <div
      v-if="!isLoading && !loadError && rules.length"
      class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_12rem]"
    >
      <NextInput
        v-model="ruleSearch"
        type="search"
        data-testid="kanban-entry-rule-search"
        :label="t('KANBAN.ENTRY_RULES.SEARCH_LABEL')"
        :placeholder="t('KANBAN.ENTRY_RULES.SEARCH_PLACEHOLDER')"
      />
      <label class="grid gap-1 text-heading-3 text-n-slate-12">
        {{ t('KANBAN.ENTRY_RULES.STATUS_FILTER_LABEL') }}
        <Select
          v-model="ruleStatus"
          full-width
          data-testid="kanban-entry-rule-status-filter"
          :options="ruleStatusOptions"
        />
      </label>
    </div>

    <p
      v-if="!isLoading && !loadError && rules.length && isFilteringRules"
      class="mb-0 text-xs text-n-slate-10"
    >
      {{ t('KANBAN.ENTRY_RULES.FILTER_REORDER_HINT') }}
    </p>

    <p v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('KANBAN.ENTRY_RULES.LOADING') }}
    </p>

    <p
      v-else-if="loadError"
      data-testid="kanban-entry-rules-load-error"
      class="text-sm text-n-ruby-11"
    >
      {{ loadError }}
    </p>

    <p
      v-else-if="!rules.length"
      data-testid="kanban-entry-rules-empty"
      class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.ENTRY_RULES.EMPTY') }}
    </p>

    <p
      v-else-if="!filteredRules.length"
      data-testid="kanban-entry-rules-filter-empty"
      class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
    >
      {{ t('KANBAN.ENTRY_RULES.FILTER_EMPTY') }}
    </p>

    <Draggable
      v-else
      :list="filteredRules"
      :disabled="isFilteringRules"
      item-key="id"
      handle=".entry-rule-handle"
      class="grid gap-2"
      @end="persistOrder"
    >
      <template #item="{ element: rule }">
        <div
          data-testid="kanban-entry-rule-row"
          class="flex items-center gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2"
        >
          <span
            v-if="!isFilteringRules"
            class="entry-rule-handle i-lucide-grip-vertical flex-none cursor-grab text-n-slate-10"
          />
          <div class="min-w-0 flex-1">
            <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
              {{ rule.name }}
            </p>
            <p
              class="mb-0 truncate text-xs text-n-slate-11"
              :title="ruleInboxSummary(rule)"
            >
              {{ ruleInboxSummary(rule) }}
            </p>
            <p
              class="mb-0 truncate text-xs text-n-slate-10"
              data-testid="kanban-entry-rule-condition-summary"
              :title="ruleConditionSummary(rule)"
            >
              {{ ruleConditionSummary(rule) }}
            </p>
          </div>
          <Switch
            :model-value="rule.active"
            data-testid="kanban-entry-rule-toggle"
            @update:model-value="toggleRule(rule)"
          />
          <Button
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="sm"
            :title="t('KANBAN.ENTRY_RULES.EDIT_RULE')"
            data-testid="kanban-entry-rule-edit"
            @click="openEditRuleModal(rule)"
          />
          <Button
            icon="i-lucide-trash"
            variant="ghost"
            color="ruby"
            size="sm"
            :title="t('KANBAN.ENTRY_RULES.REMOVE_RULE')"
            data-testid="kanban-entry-rule-remove"
            @click="openRemoveConfirmation(rule)"
          />
        </div>
      </template>
    </Draggable>

    <woot-modal
      v-model:show="showFormModal"
      :on-close="() => (showFormModal = false)"
    >
      <div class="grid gap-4 p-8">
        <h3 class="mb-0 text-lg font-medium text-n-slate-12">
          {{
            editingRuleId
              ? t('KANBAN.ENTRY_RULES.EDIT_RULE')
              : t('KANBAN.ENTRY_RULES.ADD_RULE')
          }}
        </h3>

        <NextInput
          v-model="form.name"
          data-testid="kanban-entry-rule-name"
          :label="t('KANBAN.ENTRY_RULES.NAME_LABEL')"
        />

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.allInboxes" />
          {{ t('KANBAN.ENTRY_RULES.ALL_INBOXES') }}
        </label>

        <TagMultiSelectComboBox
          v-if="!form.allInboxes"
          v-model="form.inboxIds"
          data-testid="kanban-entry-rule-inboxes"
          :options="inboxOptions"
          :placeholder="t('KANBAN.SETTINGS.INBOXES.PLACEHOLDER')"
          :search-placeholder="t('KANBAN.SETTINGS.INBOXES.SEARCH')"
          :empty-state="t('KANBAN.SETTINGS.INBOXES.EMPTY')"
        />

        <div
          v-for="field in ENTRY_RULE_FIELDS"
          :key="field.key"
          class="grid gap-2 rounded-md border border-n-weak p-3"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ fieldLabels[field.key] }}
            </span>
            <Select
              v-model="form.conditions[field.key].operator"
              :options="operatorOptionsByField[field.key]"
            />
          </div>
          <TagMultiSelectComboBox
            v-model="form.conditions[field.key].values"
            :data-testid="`kanban-entry-rule-${field.key}`"
            :options="valueOptionsByField[field.key]"
            :placeholder="t('KANBAN.ENTRY_RULES.ANY_VALUE')"
            :search-placeholder="t('KANBAN.ENTRY_RULES.SEARCH_VALUES')"
            :empty-state="t('KANBAN.ENTRY_RULES.NO_VALUES')"
          />
        </div>

        <label class="grid gap-1 text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.ENTRY_RULES.STAGE_LABEL') }}
          <Select
            v-model="form.kanbanStageId"
            data-testid="kanban-entry-rule-stage"
            :options="stageOptions"
          />
        </label>

        <p v-if="formError" class="mb-0 text-sm text-n-ruby-11">
          {{ formError }}
        </p>

        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            :label="t('KANBAN.ENTRY_RULES.CANCEL')"
            @click="showFormModal = false"
          />
          <Button
            :is-loading="isSaving"
            data-testid="kanban-entry-rule-save"
            :label="t('KANBAN.ENTRY_RULES.SAVE')"
            @click="saveRule"
          />
        </div>
      </div>
    </woot-modal>

    <woot-modal v-if="saveConfirmation" show :on-close="cancelSaveConfirmation">
      <div class="grid gap-4 p-8">
        <h3 class="mb-0 text-lg font-medium text-n-slate-12">
          {{ t('KANBAN.ENTRY_RULES.SAVE_CONFIRM_TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            t('KANBAN.ENTRY_RULES.SAVE_CONFIRM_BODY', {
              count: saveConfirmation.count,
            })
          }}
        </p>
        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            :label="t('KANBAN.ENTRY_RULES.CANCEL')"
            @click="cancelSaveConfirmation"
          />
          <Button
            :is-loading="isSaving"
            data-testid="kanban-entry-rule-save-confirm"
            :label="t('KANBAN.ENTRY_RULES.SAVE_CONFIRM')"
            @click="confirmSaveRule"
          />
        </div>
      </div>
    </woot-modal>

    <woot-modal
      v-if="importPrompt"
      show
      :on-close="() => (importPrompt = null)"
    >
      <div class="grid gap-4 p-8">
        <h3 class="mb-0 text-lg font-medium text-n-slate-12">
          {{ t('KANBAN.ENTRY_RULES.IMPORT_TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{
            t('KANBAN.ENTRY_RULES.IMPORT_BODY', { count: importPrompt.count })
          }}
        </p>
        <div class="flex justify-end gap-2">
          <Button
            variant="ghost"
            color="slate"
            :label="t('KANBAN.ENTRY_RULES.IMPORT_SKIP')"
            @click="importPrompt = null"
          />
          <Button
            :is-loading="isImporting"
            data-testid="kanban-entry-rule-import"
            :label="t('KANBAN.ENTRY_RULES.IMPORT_CONFIRM')"
            @click="runRetroactiveImport"
          />
        </div>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showRemoveConfirmation"
      :on-close="() => (showRemoveConfirmation = false)"
      :on-confirm="removeRule"
      :title="t('KANBAN.ENTRY_RULES.REMOVE_RULE')"
      :message="t('KANBAN.ENTRY_RULES.REMOVE_CONFIRM')"
      :confirm-text="t('KANBAN.ENTRY_RULES.REMOVE_RULE')"
      :reject-text="t('KANBAN.ENTRY_RULES.CANCEL')"
      :is-loading="isRemoving"
    />
  </div>
</template>
