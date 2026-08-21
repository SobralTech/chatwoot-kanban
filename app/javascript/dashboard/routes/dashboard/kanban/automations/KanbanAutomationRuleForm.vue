<script setup>
import { computed, h, ref, toRaw, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useOperators } from 'dashboard/components-next/filter/operators';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import RuleActionFields from './RuleActionFields.vue';
import {
  ACTION_NAMES,
  actionError,
  castActionParams,
  defaultActionParams,
} from './ruleActionSchema';
import { DEFAULT_CONDITION_KEY, buildFilterTypes } from './ruleConditionTypes';
import { toApiValues, toWidgetValues } from './ruleConditionValues';

const props = defineProps({
  mode: {
    type: String,
    required: true,
    validator: value => ['create', 'edit'].includes(value),
  },
  stages: {
    type: Array,
    default: () => [],
  },
  agents: {
    type: Array,
    default: () => [],
  },
  labels: {
    type: Array,
    default: () => [],
  },
  inboxes: {
    type: Array,
    default: () => [],
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  hasSimulatedLog: {
    type: Boolean,
    default: false,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
  previewRule: {
    type: Function,
    required: true,
  },
});

const emit = defineEmits(['save']);

// `overdue` is time based too, but needs no threshold: a card is past due_at or it is not.
const THRESHOLD_EVENTS = new Set(['card_stalled', 'due_soon', 'no_reply']);

const rule = defineModel('rule', { type: Object, default: null });

const { t } = useI18n();
const { operators } = useOperators();

const dialogRef = ref(null);
const conditionRefs = useTemplateRef('conditionRefs');
const errors = ref({});
const impactPreview = ref(null);
const hasReviewedImpact = ref(false);
const previewError = ref('');
const isPreviewing = ref(false);

const EVENT_NAMES = [
  'card_created',
  'stage_changed',
  'card_won',
  'card_lost',
  'card_reopened',
  'card_stalled',
  'due_soon',
  'overdue',
  'no_reply',
];

const eventOptions = computed(() =>
  EVENT_NAMES.map(value => ({
    value,
    label: t(`KANBAN.AUTOMATIONS.FORM.EVENTS.${value.toUpperCase()}`),
  }))
);

const actionOptions = computed(() =>
  ACTION_NAMES.map(value => ({
    value,
    label: t(`KANBAN.AUTOMATIONS.FORM.ACTIONS.${value.toUpperCase()}`),
  }))
);

const needsThreshold = computed(() =>
  THRESHOLD_EVENTS.has(rule.value?.event_name)
);

const thresholdPrefix = computed(() =>
  t(`KANBAN.AUTOMATIONS.FORM.TIME_THRESHOLD_PREFIX.${rule.value?.event_name}`)
);

const isEditMode = computed(() => props.mode === 'edit');
const title = computed(() =>
  isEditMode.value
    ? t('KANBAN.AUTOMATIONS.FORM.EDIT_TITLE')
    : t('KANBAN.AUTOMATIONS.FORM.ADD_TITLE')
);

const regularStageOptions = computed(() =>
  props.stages.map(stage => ({ value: stage.id, label: stage.name }))
);

const stageConditionOptions = computed(() =>
  props.stages.map(stage => ({ id: stage.id, name: stage.name }))
);

const agentConditionOptions = computed(() =>
  props.agents.map(agent => ({
    id: agent.id,
    name: agent.name || agent.email,
  }))
);

const agentActionOptions = computed(() =>
  props.agents.map(agent => ({
    value: agent.id,
    label: agent.name || agent.email,
  }))
);

const labelConditionOptions = computed(() =>
  props.labels.map(label => ({ id: label.title, name: label.title }))
);

const labelActionOptions = computed(() =>
  props.labels.map(label => ({ value: label.title, label: label.title }))
);

const inboxConditionOptions = computed(() =>
  props.inboxes.map(inbox => ({ id: inbox.id, name: inbox.name }))
);

const reasonOptions = computed(() =>
  props.reasons
    .filter(reason => reason.reasonType === 'lost')
    .map(reason => ({ value: reason.id, label: reason.title }))
);

const reasonConditionOptions = computed(() =>
  props.reasons.map(reason => ({ id: reason.id, name: reason.title }))
);

const priorityOptions = computed(() => [
  {
    value: 'urgent',
    label: t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
  },
  { value: 'high', label: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
  { value: 'medium', label: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
  { value: 'low', label: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
]);

const priorityConditionOptions = computed(() =>
  priorityOptions.value.map(option => ({
    id: option.value,
    name: option.label,
  }))
);

const originLabels = computed(() => ({
  manual: t('KANBAN.AUTOMATIONS.FORM.ORIGINS.MANUAL'),
  conversation: t('KANBAN.AUTOMATIONS.FORM.ORIGINS.CONVERSATION'),
  import: t('KANBAN.AUTOMATIONS.FORM.ORIGINS.IMPORT'),
  recurrence: t('KANBAN.AUTOMATIONS.FORM.ORIGINS.RECURRENCE'),
}));

const originOptions = computed(() =>
  ['manual', 'conversation', 'import', 'recurrence'].map(value => ({
    id: value,
    name: originLabels.value[value],
  }))
);

const customOperatorLabels = computed(() => ({
  greater_than: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.greater_than'),
  less_than: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.less_than'),
  is_one_of: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.is_one_of'),
  includes: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.includes'),
}));

const operator = (value, inputOverride = null) => {
  if (operators.value[value]) {
    return { ...operators.value[value], inputOverride };
  }

  return {
    value,
    label: customOperatorLabels.value[value] || value,
    hasInput: !['is_present', 'is_not_present'].includes(value),
    inputOverride,
    icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
  };
};

const operatorsFor = values => values.map(value => operator(value));

const conditionOptionSets = computed(() => ({
  stages: stageConditionOptions.value,
  priorities: priorityConditionOptions.value,
  labels: labelConditionOptions.value,
  agents: agentConditionOptions.value,
  inboxes: inboxConditionOptions.value,
  reasons: reasonConditionOptions.value,
  origins: originOptions.value,
}));

const filterTypes = computed(() =>
  buildFilterTypes({
    t,
    optionsFor: key => conditionOptionSets.value[key] || [],
    operatorsFor,
  })
);

const displayedConditions = computed(() =>
  (rule.value?.conditions || []).map((condition, index) => ({
    condition,
    index,
  }))
);

const makeCondition = (attributeKey = DEFAULT_CONDITION_KEY) => {
  const type = filterTypes.value.find(
    item => item.attributeKey === attributeKey
  );
  return {
    attribute_key: attributeKey,
    filter_operator: type?.filterOperators?.[0]?.value || 'equal_to',
    values: [],
  };
};

const normalizeConditionForUi = condition => {
  toWidgetValues(
    condition,
    filterTypes.value.find(
      item => item.attributeKey === condition.attribute_key
    ),
    {
      trueLabel: t('FILTER.ATTRIBUTE_LABELS.TRUE'),
      falseLabel: t('FILTER.ATTRIBUTE_LABELS.FALSE'),
    }
  );
};

const normalizeConditionsForUi = () => {
  rule.value?.conditions?.forEach(normalizeConditionForUi);
};

watch(filterTypes, normalizeConditionsForUi, { deep: true });

const ensureThreshold = () => {
  if (!rule.value || !needsThreshold.value) return;
  if (!rule.value.threshold_hours) rule.value.threshold_hours = 24;
};

const resetForEvent = () => {
  if (!rule.value) return;

  if (!rule.value.conditions?.length) {
    rule.value.conditions = [makeCondition()];
  }
  if (!needsThreshold.value) rule.value.threshold_hours = null;
  ensureThreshold();
  errors.value = {};
};

const onThresholdChange = value => {
  rule.value.threshold_hours = value === '' ? null : Number(value);
};

const appendCondition = () => {
  if (!rule.value) return;
  rule.value.conditions.push(makeCondition());
};

const removeCondition = index => {
  if (!rule.value) return;
  rule.value.conditions.splice(index, 1);
};

const appendAction = () => {
  if (!rule.value) return;
  rule.value.actions.push({
    action_name: 'move_to_stage',
    action_params: defaultActionParams('move_to_stage'),
  });
};

const removeAction = index => {
  if (!rule.value) return;
  rule.value.actions.splice(index, 1);
};

const onActionChange = (action, actionName) => {
  action.action_params = defaultActionParams(actionName);
};

const variables = computed(() => [
  {
    key: 'contact_name',
    label: t('KANBAN.AUTOMATIONS.FORM.VARIABLE_NAMES.CONTACT_NAME'),
  },
  {
    key: 'agent_name',
    label: t('KANBAN.AUTOMATIONS.FORM.VARIABLE_NAMES.AGENT_NAME'),
  },
  {
    key: 'card_subject',
    label: t('KANBAN.AUTOMATIONS.FORM.VARIABLE_NAMES.CARD_SUBJECT'),
  },
  {
    key: 'total',
    label: t('KANBAN.AUTOMATIONS.FORM.VARIABLE_NAMES.TOTAL'),
  },
  {
    key: 'card.stage.name',
    label: t('KANBAN.AUTOMATIONS.FORM.VARIABLE_NAMES.STAGE'),
  },
]);

const buildPayload = () => {
  const payload = structuredClone(toRaw(rule.value));
  payload.name = payload.name.trim();
  payload.description = (payload.description || '').trim();
  payload.conditions = (payload.conditions || []).map(condition => ({
    attribute_key: condition.attribute_key,
    filter_operator: condition.filter_operator,
    values: toApiValues(condition),
  }));
  payload.actions = (payload.actions || []).map(action => ({
    action_name: action.action_name,
    action_params: castActionParams(action),
  }));
  payload.dry_run = Boolean(payload.dry_run);

  return payload;
};

const validateAction = (action, index) => {
  const message = actionError(action);
  if (message) errors.value[`action_${index}`] = message;
};

const resetValidation = () => {
  errors.value = {};
  conditionRefs.value?.forEach(condition => condition.resetValidation());
};

const actionErrorMessage = error =>
  t(`KANBAN.AUTOMATIONS.FORM.ERRORS.${error}`);

const validateForm = () => {
  errors.value = {};
  if (!rule.value.name?.trim()) errors.value.name = 'NAME_REQUIRED';
  if (!rule.value.event_name) errors.value.event_name = 'EVENT_REQUIRED';

  const conditionComponents = Array.isArray(conditionRefs.value)
    ? conditionRefs.value
    : [conditionRefs.value].filter(Boolean);
  const conditionsValid = conditionComponents.every(condition =>
    condition.validate()
  );

  if (needsThreshold.value && !(Number(rule.value.threshold_hours) > 0)) {
    errors.value.threshold = 'THRESHOLD_REQUIRED';
  }
  if (!rule.value.conditions?.length)
    errors.value.conditions = 'CONDITIONS_REQUIRED';
  if (!rule.value.actions?.length) errors.value.actions = 'ACTIONS_REQUIRED';
  rule.value.actions?.forEach(validateAction);

  return conditionsValid && Object.keys(errors.value).length === 0;
};

const requestPreview = async () => {
  previewError.value = '';
  if (!validateForm()) return;

  isPreviewing.value = true;
  try {
    const response = await props.previewRule(buildPayload());
    impactPreview.value = response.count;
    hasReviewedImpact.value = true;
  } catch (error) {
    previewError.value =
      error?.response?.data?.error ||
      error?.message ||
      t('KANBAN.AUTOMATIONS.FORM.PREVIEW_ERROR');
  } finally {
    isPreviewing.value = false;
  }
};

const submit = () => {
  if (!hasReviewedImpact.value) {
    requestPreview();
    return;
  }

  if (!validateForm()) return;
  emit('save', buildPayload());
};

// Simulation is one boolean, so it gets one button: the one that leaves it, or the one
// that comes back. Going live needs a simulated run behind it, and the line under the
// button says so when there is not one yet.
const setSimulation = value => {
  if (!rule.value) return;
  if (!value && !props.hasSimulatedLog) return;

  rule.value.dry_run = value;
};

const open = () => {
  resetValidation();
  impactPreview.value = null;
  hasReviewedImpact.value = false;
  previewError.value = '';
  if (rule.value) {
    rule.value.conditions ||= [makeCondition()];
    rule.value.actions ||= [
      {
        action_name: 'move_to_stage',
        action_params: defaultActionParams('move_to_stage'),
      },
    ];
    normalizeConditionsForUi();
    ensureThreshold();
  }
  dialogRef.value?.open();
};

const close = () => {
  resetValidation();
  dialogRef.value?.close();
};

watch(
  () => rule.value?.event_name,
  () => {
    if (dialogRef.value) ensureThreshold();
  }
);

watch(
  rule,
  () => {
    if (isPreviewing.value) return;

    impactPreview.value = null;
    hasReviewedImpact.value = false;
  },
  { deep: true }
);

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    position="top"
    :title="title"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
  >
    <div v-if="rule" class="grid w-full gap-6">
      <p
        v-if="errors.name || errors.event_name"
        class="rounded-md bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        {{ t('KANBAN.AUTOMATIONS.FORM.REQUIRED_FIELDS') }}
      </p>

      <label class="grid gap-1 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.AUTOMATIONS.FORM.NAME') }}
        <input
          v-model="rule.name"
          data-testid="kanban-automation-rule-name"
          type="text"
          :placeholder="t('KANBAN.AUTOMATIONS.FORM.NAME_PLACEHOLDER')"
          class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 font-normal outline-none placeholder:text-n-slate-10 focus:border-n-brand"
        />
      </label>

      <label class="grid gap-1 text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.AUTOMATIONS.FORM.DESCRIPTION') }}
        <textarea
          v-model="rule.description"
          data-testid="kanban-automation-rule-description"
          rows="2"
          :placeholder="t('KANBAN.AUTOMATIONS.FORM.DESCRIPTION_PLACEHOLDER')"
          class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 font-normal outline-none placeholder:text-n-slate-10 focus:border-n-brand"
        />
      </label>

      <section class="grid gap-3">
        <h2 class="text-base font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.FORM.WHEN') }}
        </h2>
        <Select
          v-model="rule.event_name"
          data-testid="kanban-automation-rule-event"
          :options="eventOptions"
          full-width
          @update:model-value="resetForEvent"
        />
        <div
          v-if="needsThreshold"
          class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
        >
          <span>{{ thresholdPrefix }}</span>
          <input
            :value="rule.threshold_hours ?? ''"
            data-testid="kanban-automation-rule-threshold"
            type="number"
            min="1"
            class="w-24 rounded-md border border-n-weak bg-n-surface-1 px-2 py-1.5 outline-none focus:border-n-brand"
            @input="onThresholdChange($event.target.value)"
          />
          <span>{{ t('KANBAN.AUTOMATIONS.FORM.TIME_THRESHOLD_SUFFIX') }}</span>
        </div>
        <p v-if="errors.threshold" class="text-sm text-n-ruby-11">
          {{ t('KANBAN.AUTOMATIONS.FORM.THRESHOLD_REQUIRED') }}
        </p>
      </section>

      <section class="grid gap-3">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.AUTOMATIONS.FORM.IF') }}
            </h2>
            <p class="text-xs text-n-slate-10">
              {{ t('KANBAN.AUTOMATIONS.FORM.ALL_CONDITIONS_HINT') }}
            </p>
          </div>
          <Button
            icon="i-lucide-plus"
            :label="t('KANBAN.AUTOMATIONS.FORM.ADD_CONDITION')"
            color="slate"
            size="sm"
            data-testid="kanban-automation-add-condition"
            @click="appendCondition"
          />
        </div>

        <div
          class="grid gap-3 rounded-xl border border-n-weak p-3"
          :class="{ 'border-n-ruby-8 bg-n-ruby-2/30': errors.conditions }"
        >
          <p
            v-if="displayedConditions.length === 0"
            class="text-sm text-n-slate-11"
          >
            {{ t('KANBAN.AUTOMATIONS.FORM.NO_CONDITIONS') }}
          </p>
          <ConditionRow
            v-for="item in displayedConditions"
            :key="item.index"
            ref="conditionRefs"
            v-model:attribute-key="rule.conditions[item.index].attribute_key"
            v-model:filter-operator="
              rule.conditions[item.index].filter_operator
            "
            v-model:values="rule.conditions[item.index].values"
            :filter-types="filterTypes"
            :show-query-operator="false"
            @remove="removeCondition(item.index)"
          />
        </div>
      </section>

      <section class="grid gap-3">
        <div class="flex items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.AUTOMATIONS.FORM.THEN') }}
            </h2>
            <p class="text-xs text-n-slate-10">
              {{ t('KANBAN.AUTOMATIONS.FORM.ACTIONS_HINT') }}
            </p>
          </div>
          <Button
            icon="i-lucide-plus"
            :label="t('KANBAN.AUTOMATIONS.FORM.ADD_ACTION')"
            color="slate"
            size="sm"
            data-testid="kanban-automation-add-action"
            @click="appendAction"
          />
        </div>

        <div
          class="grid gap-4 rounded-xl border border-n-weak p-3"
          :class="{ 'border-n-ruby-8 bg-n-ruby-2/30': errors.actions }"
        >
          <div
            v-for="(action, index) in rule.actions"
            :key="index"
            class="grid gap-3 border-b border-n-weak pb-4 last:border-b-0 last:pb-0"
            data-testid="kanban-automation-action"
          >
            <div class="flex items-center gap-2">
              <Select
                v-model="action.action_name"
                class="min-w-0 flex-1"
                :options="actionOptions"
                full-width
                @update:model-value="onActionChange(action, $event)"
              />
              <Button
                icon="i-lucide-trash"
                variant="ghost"
                color="ruby"
                size="sm"
                :title="t('KANBAN.AUTOMATIONS.FORM.REMOVE_ACTION')"
                @click="removeAction(index)"
              />
            </div>

            <RuleActionFields
              v-model:action="rule.actions[index]"
              :stages="regularStageOptions"
              :agents="agentActionOptions"
              :labels="labelActionOptions"
              :reasons="reasonOptions"
              :priorities="priorityOptions"
              :variables="variables"
            />

            <p v-if="errors[`action_${index}`]" class="text-sm text-n-ruby-11">
              {{ actionErrorMessage(errors[`action_${index}`]) }}
            </p>
          </div>
        </div>
      </section>

      <section
        class="grid gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-4"
      >
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.AUTOMATIONS.FORM.SIMULATION_LABEL') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('KANBAN.AUTOMATIONS.FORM.SIMULATION_HELP') }}
        </p>
        <Button
          v-if="rule.dry_run"
          icon="i-lucide-zap"
          :label="t('KANBAN.AUTOMATIONS.FORM.ACTIVATE_FOR_REAL')"
          color="teal"
          size="sm"
          :disabled="!hasSimulatedLog"
          data-testid="kanban-automation-activate"
          @click="setSimulation(false)"
        />
        <Button
          v-else
          icon="i-lucide-flask-conical"
          :label="t('KANBAN.AUTOMATIONS.FORM.BACK_TO_SIMULATION')"
          variant="faded"
          color="slate"
          size="sm"
          data-testid="kanban-automation-simulate"
          @click="setSimulation(true)"
        />
        <p
          v-if="rule.dry_run && !hasSimulatedLog"
          class="mb-0 text-xs text-n-amber-11"
        >
          {{ t('KANBAN.AUTOMATIONS.FORM.ACTIVATE_BLOCKED') }}
        </p>
      </section>

      <p
        v-if="impactPreview !== null"
        class="rounded-md bg-n-teal-2 px-3 py-2 text-sm text-n-teal-11"
        data-testid="kanban-automation-impact-preview"
      >
        {{
          t('KANBAN.AUTOMATIONS.FORM.IMPACT_PREVIEW', { count: impactPreview })
        }}
      </p>
      <p v-if="previewError" class="text-sm text-n-ruby-11">
        {{ previewError }}
      </p>

      <div class="flex flex-wrap justify-end gap-2 border-t border-n-weak pt-4">
        <Button
          variant="faded"
          color="slate"
          type="button"
          :label="t('KANBAN.AUTOMATIONS.FORM.CANCEL')"
          @click="close"
        />
        <Button
          color="blue"
          type="button"
          :label="
            hasReviewedImpact
              ? t('KANBAN.AUTOMATIONS.FORM.SAVE')
              : t('KANBAN.AUTOMATIONS.FORM.PREVIEW_AND_CONTINUE')
          "
          :is-loading="isPreviewing || isSaving"
          :disabled="isPreviewing || isSaving"
          data-testid="kanban-automation-rule-submit"
          @click="submit"
        />
      </div>
    </div>
  </Dialog>
</template>
