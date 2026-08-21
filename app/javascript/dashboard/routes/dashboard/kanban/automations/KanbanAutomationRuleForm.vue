<script setup>
import { computed, h, ref, toRaw, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useOperators } from 'dashboard/components-next/filter/operators';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

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

const TIME_BASED_EVENTS = new Set(['card_stalled', 'due_soon', 'no_reply']);

const NUMERIC_CONDITIONS = new Set([
  'stage_id',
  'previous_stage_id',
  'assignee_id',
  'inbox_id',
  'total_value',
  'hours_in_stage',
  'reason_id',
]);

const MESSAGE_ACTIONS = new Set([
  'send_message',
  'create_note',
  'send_private_note',
]);

const rule = defineModel('rule', { type: Object, default: null });

const { t } = useI18n();
const { operators } = useOperators();

const dialogRef = ref(null);
const conditionRefs = useTemplateRef('conditionRefs');
const errors = ref({});
const impactPreview = ref(null);
const previewError = ref('');
const isPreviewing = ref(false);

const eventOptions = computed(() => [
  {
    value: 'card_created',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_CREATED'),
  },
  {
    value: 'stage_changed',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.STAGE_CHANGED'),
  },
  {
    value: 'card_won',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_WON'),
  },
  {
    value: 'card_lost',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_LOST'),
  },
  {
    value: 'card_reopened',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_REOPENED'),
  },
  {
    value: 'card_stalled',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_STALLED'),
  },
  {
    value: 'due_soon',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.DUE_SOON'),
  },
  {
    value: 'overdue',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.OVERDUE'),
  },
  {
    value: 'no_reply',
    label: t('KANBAN.AUTOMATIONS.FORM.EVENTS.NO_REPLY'),
  },
]);

const actionOptions = computed(() => [
  {
    value: 'move_to_stage',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.MOVE_TO_STAGE'),
  },
  {
    value: 'assign_agents',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.ASSIGN_AGENTS'),
  },
  {
    value: 'set_priority',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.SET_PRIORITY'),
  },
  {
    value: 'add_label',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.ADD_LABEL'),
  },
  {
    value: 'remove_label',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.REMOVE_LABEL'),
  },
  {
    value: 'send_message',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.SEND_MESSAGE'),
  },
  {
    value: 'create_note',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.CREATE_NOTE'),
  },
  {
    value: 'send_private_note',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.SEND_PRIVATE_NOTE'),
  },
  {
    value: 'set_due_at',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.SET_DUE_AT'),
  },
  {
    value: 'mark_as_lost',
    label: t('KANBAN.AUTOMATIONS.FORM.ACTIONS.MARK_AS_LOST'),
  },
]);

const isTimeBasedEvent = computed(() =>
  TIME_BASED_EVENTS.has(rule.value?.event_name)
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
    .filter(reason => (reason.reasonType || reason.reason_type) === 'lost')
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

const filterTypes = computed(() => [
  {
    attributeKey: 'stage_id',
    value: 'stage_id',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.STAGE'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.STAGE'),
    inputType: 'multiSelect',
    options: stageConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'previous_stage_id',
    value: 'previous_stage_id',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PREVIOUS_STAGE'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PREVIOUS_STAGE'),
    inputType: 'multiSelect',
    options: stageConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'priority',
    value: 'priority',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PRIORITY'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PRIORITY'),
    inputType: 'multiSelect',
    options: priorityConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'labels',
    value: 'labels',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.LABELS'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.LABELS'),
    inputType: 'multiSelect',
    options: labelConditionOptions.value,
    filterOperators: operatorsFor(['includes', 'is_not_present']),
  },
  {
    attributeKey: 'assignee_id',
    value: 'assignee_id',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ASSIGNEE'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ASSIGNEE'),
    inputType: 'multiSelect',
    options: agentConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'inbox_id',
    value: 'inbox_id',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.INBOX'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.INBOX'),
    inputType: 'multiSelect',
    options: inboxConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'total_value',
    value: 'total_value',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.TOTAL_VALUE'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.TOTAL_VALUE'),
    inputType: 'number',
    options: [],
    filterOperators: operatorsFor([
      'equal_to',
      'not_equal_to',
      'greater_than',
      'less_than',
    ]),
  },
  {
    attributeKey: 'hours_in_stage',
    value: 'hours_in_stage',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.HOURS_IN_STAGE'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.HOURS_IN_STAGE'),
    inputType: 'number',
    options: [],
    filterOperators: operatorsFor([
      'equal_to',
      'not_equal_to',
      'greater_than',
      'less_than',
    ]),
  },
  {
    attributeKey: 'reason_id',
    value: 'reason_id',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.REASON'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.REASON'),
    inputType: 'multiSelect',
    options: reasonConditionOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'origin',
    value: 'origin',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ORIGIN'),
    attributeName: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ORIGIN'),
    inputType: 'multiSelect',
    options: originOptions.value,
    filterOperators: operatorsFor(['equal_to', 'not_equal_to', 'is_one_of']),
  },
  {
    attributeKey: 'contact_has_open_card',
    value: 'contact_has_open_card',
    label: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.CONTACT_HAS_OPEN_CARD'),
    attributeName: t(
      'KANBAN.AUTOMATIONS.FORM.CONDITIONS.CONTACT_HAS_OPEN_CARD'
    ),
    inputType: 'booleanSelect',
    options: [],
    filterOperators: operatorsFor(['equal_to', 'not_equal_to']),
  },
]);

const displayedConditions = computed(() =>
  (rule.value?.conditions || [])
    .map((condition, index) => ({ condition, index }))
    .filter(
      ({ condition }) =>
        !(
          isTimeBasedEvent.value && condition.attribute_key === 'hours_in_stage'
        )
    )
);

const thresholdCondition = computed(() =>
  (rule.value?.conditions || []).find(
    condition => condition.attribute_key === 'hours_in_stage'
  )
);

const thresholdHours = computed(
  () => thresholdCondition.value?.values?.[0] || ''
);

const makeCondition = attributeKey => {
  const type = filterTypes.value.find(
    item => item.attributeKey === attributeKey
  );
  return {
    attribute_key: attributeKey,
    filter_operator: type?.filterOperators?.[0]?.value || 'equal_to',
    values: [],
  };
};

const normalizedValue = value => {
  if (value && typeof value === 'object' && 'id' in value) return value.id;
  return value;
};

const normalizeConditionForUi = condition => {
  const filter = filterTypes.value.find(
    item => item.attributeKey === condition.attribute_key
  );
  const values = Array.isArray(condition.values)
    ? condition.values
    : [condition.values];

  if (filter?.inputType === 'multiSelect') {
    if (['is_present', 'is_not_present'].includes(condition.filter_operator)) {
      condition.values = [];
      return;
    }

    condition.values = values
      .map(value => {
        const valueId = normalizedValue(value);
        return (
          filter.options.find(
            option => String(option.id) === String(valueId)
          ) ||
          (value && typeof value === 'object'
            ? value
            : { id: valueId, name: String(valueId) })
        );
      })
      .filter(Boolean);
    return;
  }

  if (filter?.inputType === 'booleanSelect') {
    const value = normalizedValue(values[0]);
    if (value === undefined || value === null || value === '') {
      condition.values = {};
      return;
    }

    const booleanValue = value === true || value === 'true';
    condition.values = {
      id: booleanValue,
      name: booleanValue
        ? t('FILTER.ATTRIBUTE_LABELS.TRUE')
        : t('FILTER.ATTRIBUTE_LABELS.FALSE'),
    };
    return;
  }

  if (filter?.inputType === 'number') {
    condition.values = values[0] ?? '';
  }
};

const normalizeConditionsForUi = () => {
  rule.value?.conditions?.forEach(normalizeConditionForUi);
};

watch(filterTypes, normalizeConditionsForUi, { deep: true });

const ensureTimeCondition = () => {
  if (!rule.value || !isTimeBasedEvent.value) return;

  const condition = thresholdCondition.value;
  if (condition) {
    if (!condition.values?.length) condition.values = [24];
    condition.filter_operator = 'greater_than';
    return;
  }

  rule.value.conditions.unshift({
    attribute_key: 'hours_in_stage',
    filter_operator: 'greater_than',
    values: [24],
  });
};

const resetForEvent = () => {
  if (!rule.value) return;

  rule.value.conditions = (rule.value.conditions || []).filter(
    condition => condition.attribute_key !== 'hours_in_stage'
  );
  if (!rule.value.conditions.length) {
    rule.value.conditions = [makeCondition('stage_id')];
  }
  ensureTimeCondition();
  errors.value = {};
};

const onThresholdChange = value => {
  if (!thresholdCondition.value) ensureTimeCondition();
  thresholdCondition.value.values = value === '' ? [] : [Number(value)];
};

const appendCondition = () => {
  if (!rule.value) return;
  rule.value.conditions.push(makeCondition('stage_id'));
};

const removeCondition = index => {
  if (!rule.value) return;
  rule.value.conditions.splice(index, 1);
};

const defaultActionParams = actionName => {
  switch (actionName) {
    case 'move_to_stage':
      return { stage_id: props.stages[0]?.id || '' };
    case 'assign_agents':
      return { agent_ids: [], mode: 'set' };
    case 'set_priority':
      return { priority: '' };
    case 'add_label':
    case 'remove_label':
      return { labels: [] };
    case 'send_message':
    case 'create_note':
    case 'send_private_note':
      return { content: '' };
    case 'set_due_at':
      return { days: 1, business_days: false };
    case 'mark_as_lost':
      return { reason_id: reasonOptions.value[0]?.value || '' };
    default:
      return {};
  }
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

const previewValues = {
  contact_name: 'Maria Silva',
  agent_name: 'João Costa',
  card_subject: 'Orçamento #4521',
  total: 'R$ 1,250.00',
  'card.stage.name': 'Negociação',
};

const renderPreview = content =>
  String(content || '').replace(/{{\s*([^}]+?)\s*}}/g, (_match, key) => {
    return previewValues[key.trim()] || `{{${key.trim()}}}`;
  });

const appendVariable = (action, key) => {
  action.action_params.content = `${action.action_params.content || ''}{{${key}}}`;
};

const normalizeConditionValues = condition => {
  const values = Array.isArray(condition.values)
    ? condition.values
    : [condition.values];
  const normalized = values
    .map(normalizedValue)
    .filter(value => value !== undefined && value !== null && value !== '');

  if (condition.attribute_key === 'contact_has_open_card') {
    return normalized.map(value => value === true || value === 'true');
  }

  if (NUMERIC_CONDITIONS.has(condition.attribute_key)) {
    return normalized.map(value => Number(value));
  }

  return normalized;
};

const buildPayload = () => {
  const payload = structuredClone(toRaw(rule.value));
  payload.name = payload.name.trim();
  payload.description = (payload.description || '').trim();
  payload.conditions = (payload.conditions || []).map(condition => ({
    attribute_key: condition.attribute_key,
    filter_operator: condition.filter_operator,
    values: normalizeConditionValues(condition),
  }));
  payload.actions = (payload.actions || []).map(action => {
    const actionParams = structuredClone(action.action_params || {});
    if (actionParams.agent_ids) {
      actionParams.agent_ids = actionParams.agent_ids.map(Number);
    }
    if (actionParams.stage_id)
      actionParams.stage_id = Number(actionParams.stage_id);
    if (actionParams.reason_id)
      actionParams.reason_id = Number(actionParams.reason_id);
    if (actionParams.days !== undefined)
      actionParams.days = Number(actionParams.days);
    return {
      action_name: action.action_name,
      action_params: actionParams,
    };
  });
  payload.dry_run = Boolean(payload.dry_run);

  return payload;
};

const validateAction = (action, index) => {
  const params = action.action_params || {};
  let message = '';

  switch (action.action_name) {
    case 'move_to_stage':
      if (!params.stage_id) message = 'ACTION_STAGE_REQUIRED';
      break;
    case 'assign_agents':
      if (
        !Array.isArray(params.agent_ids) ||
        (params.mode !== 'round_robin' && !params.agent_ids.length)
      ) {
        message = 'ACTION_AGENTS_REQUIRED';
      }
      if (!params.mode) message = 'ACTION_MODE_REQUIRED';
      break;
    case 'set_priority':
      if (!params.priority) message = 'ACTION_PRIORITY_REQUIRED';
      break;
    case 'add_label':
    case 'remove_label':
      if (!params.labels?.length) message = 'ACTION_LABELS_REQUIRED';
      break;
    case 'send_message':
    case 'create_note':
    case 'send_private_note':
      if (!params.content?.trim()) message = 'ACTION_CONTENT_REQUIRED';
      break;
    case 'set_due_at':
      if (!Number(params.days) || Number(params.days) < 1) {
        message = 'ACTION_DAYS_REQUIRED';
      }
      break;
    case 'mark_as_lost':
      if (!params.reason_id) message = 'ACTION_REASON_REQUIRED';
      break;
    default:
      break;
  }

  if (message) errors.value[`action_${index}`] = message;
};

const resetValidation = () => {
  errors.value = {};
  conditionRefs.value?.forEach(condition => condition.resetValidation());
};

const actionErrorMessages = computed(() => ({
  ACTION_STAGE_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_STAGE_REQUIRED'
  ),
  ACTION_AGENTS_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_AGENTS_REQUIRED'
  ),
  ACTION_MODE_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_MODE_REQUIRED'
  ),
  ACTION_PRIORITY_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_PRIORITY_REQUIRED'
  ),
  ACTION_LABELS_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_LABELS_REQUIRED'
  ),
  ACTION_CONTENT_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_CONTENT_REQUIRED'
  ),
  ACTION_DAYS_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_DAYS_REQUIRED'
  ),
  ACTION_REASON_REQUIRED: t(
    'KANBAN.AUTOMATIONS.FORM.ERRORS.ACTION_REASON_REQUIRED'
  ),
}));

const actionErrorMessage = error =>
  actionErrorMessages.value[error] ||
  t('KANBAN.AUTOMATIONS.FORM.REQUIRED_FIELDS');

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

  if (
    isTimeBasedEvent.value &&
    (!thresholdHours.value || Number(thresholdHours.value) <= 0)
  ) {
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
  if (impactPreview.value === null) {
    requestPreview();
    return;
  }

  if (!validateForm()) return;
  emit('save', buildPayload());
};

const activateForReal = () => {
  if (!props.hasSimulatedLog || !rule.value) return;
  rule.value.dry_run = false;
};

const open = () => {
  resetValidation();
  impactPreview.value = null;
  previewError.value = '';
  if (rule.value) {
    rule.value.conditions ||= [makeCondition('stage_id')];
    rule.value.actions ||= [
      {
        action_name: 'move_to_stage',
        action_params: defaultActionParams('move_to_stage'),
      },
    ];
    normalizeConditionsForUi();
    ensureTimeCondition();
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
    if (dialogRef.value && isTimeBasedEvent.value) ensureTimeCondition();
  }
);

watch(
  rule,
  () => {
    if (!isPreviewing.value) impactPreview.value = null;
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
          v-if="isTimeBasedEvent"
          class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
        >
          <span>{{ t('KANBAN.AUTOMATIONS.FORM.TIME_THRESHOLD_PREFIX') }}</span>
          <input
            :value="thresholdHours"
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

            <Select
              v-if="action.action_name === 'move_to_stage'"
              v-model="action.action_params.stage_id"
              :options="regularStageOptions"
              :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_STAGE')"
              full-width
            />

            <div
              v-else-if="action.action_name === 'assign_agents'"
              class="grid gap-3"
            >
              <TagMultiSelectComboBox
                v-model="action.action_params.agent_ids"
                :options="agentActionOptions"
                :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_AGENTS')"
                :search-placeholder="t('KANBAN.AUTOMATIONS.FORM.SEARCH_AGENTS')"
                :empty-state="t('KANBAN.AUTOMATIONS.FORM.NO_AGENTS')"
              />
              <Select
                v-model="action.action_params.mode"
                :options="[
                  {
                    value: 'set',
                    label: t('KANBAN.AUTOMATIONS.FORM.ASSIGN_MODES.SET'),
                  },
                  {
                    value: 'add',
                    label: t('KANBAN.AUTOMATIONS.FORM.ASSIGN_MODES.ADD'),
                  },
                  {
                    value: 'round_robin',
                    label: t(
                      'KANBAN.AUTOMATIONS.FORM.ASSIGN_MODES.ROUND_ROBIN'
                    ),
                  },
                ]"
                full-width
              />
            </div>

            <Select
              v-else-if="action.action_name === 'set_priority'"
              v-model="action.action_params.priority"
              :options="priorityOptions"
              :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_PRIORITY')"
              full-width
            />

            <TagMultiSelectComboBox
              v-else-if="
                ['add_label', 'remove_label'].includes(action.action_name)
              "
              v-model="action.action_params.labels"
              :options="labelActionOptions"
              :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_LABELS')"
              :search-placeholder="t('KANBAN.AUTOMATIONS.FORM.SEARCH_LABELS')"
              :empty-state="t('KANBAN.AUTOMATIONS.FORM.NO_LABELS')"
            />

            <div
              v-else-if="MESSAGE_ACTIONS.has(action.action_name)"
              class="grid gap-3"
            >
              <div class="grid gap-2 lg:grid-cols-[minmax(0,1fr)_13rem]">
                <textarea
                  v-model="action.action_params.content"
                  rows="4"
                  :placeholder="
                    t('KANBAN.AUTOMATIONS.FORM.MESSAGE_PLACEHOLDER')
                  "
                  class="min-w-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                />
                <div
                  class="grid content-start gap-2 rounded-md bg-n-alpha-2 p-2"
                >
                  <p class="text-xs font-medium text-n-slate-11">
                    {{ t('KANBAN.AUTOMATIONS.FORM.VARIABLES') }}
                  </p>
                  <button
                    v-for="variable in variables"
                    :key="variable.key"
                    type="button"
                    class="truncate rounded px-2 py-1 text-left text-xs text-n-blue-11 hover:bg-n-alpha-2"
                    @click="appendVariable(action, variable.key)"
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
                  {{
                    renderPreview(action.action_params.content) ||
                    t('KANBAN.AUTOMATIONS.FORM.EMPTY_MESSAGE')
                  }}
                </p>
              </div>
            </div>

            <div
              v-else-if="action.action_name === 'set_due_at'"
              class="grid gap-3"
            >
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
                <input
                  v-model="action.action_params.business_days"
                  type="checkbox"
                />
                {{ t('KANBAN.AUTOMATIONS.FORM.BUSINESS_DAYS') }}
              </label>
            </div>

            <Select
              v-else-if="action.action_name === 'mark_as_lost'"
              v-model="action.action_params.reason_id"
              :options="reasonOptions"
              :placeholder="t('KANBAN.AUTOMATIONS.FORM.SELECT_REASON')"
              full-width
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
        <label
          class="flex items-center justify-between gap-3 text-sm font-medium text-n-slate-12"
        >
          <span>{{ t('KANBAN.AUTOMATIONS.FORM.SIMULATION_LABEL') }}</span>
          <input
            v-model="rule.dry_run"
            type="checkbox"
            :disabled="rule.dry_run && !hasSimulatedLog"
            class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
          />
        </label>
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.AUTOMATIONS.FORM.SIMULATION_HELP') }}
        </p>
        <Button
          v-if="rule.dry_run"
          icon="i-lucide-zap"
          :label="t('KANBAN.AUTOMATIONS.FORM.ACTIVATE_FOR_REAL')"
          color="teal"
          size="sm"
          :disabled="!hasSimulatedLog"
          :title="
            !hasSimulatedLog
              ? t('KANBAN.AUTOMATIONS.FORM.ACTIVATE_BLOCKED')
              : ''
          "
          data-testid="kanban-automation-activate"
          @click="activateForReal"
        />
        <p
          v-if="rule.dry_run && !hasSimulatedLog"
          class="text-xs text-n-amber-11"
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
            impactPreview === null
              ? t('KANBAN.AUTOMATIONS.FORM.PREVIEW_AND_CONTINUE')
              : t('KANBAN.AUTOMATIONS.FORM.SAVE')
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
