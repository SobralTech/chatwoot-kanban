// The condition catalogue. Each row is [attributeKey, inputType, operators], and the
// options come from a lookup the form passes in, so this stays a table rather than
// eleven near-identical object literals.
const SELECT_OPERATORS = ['equal_to', 'not_equal_to', 'is_one_of'];
const NUMERIC_OPERATORS = [
  'equal_to',
  'not_equal_to',
  'greater_than',
  'less_than',
];
const BOOLEAN_OPERATORS = ['equal_to', 'not_equal_to'];

const CONDITIONS = [
  ['stage_id', 'multiSelect', 'STAGE', 'stages'],
  ['previous_stage_id', 'multiSelect', 'PREVIOUS_STAGE', 'stages'],
  ['priority', 'multiSelect', 'PRIORITY', 'priorities'],
  ['labels', 'multiSelect', 'LABELS', 'labels', ['includes', 'is_not_present']],
  ['assignee_id', 'multiSelect', 'ASSIGNEE', 'agents'],
  ['inbox_id', 'multiSelect', 'INBOX', 'inboxes'],
  ['total_value', 'number', 'TOTAL_VALUE', null, NUMERIC_OPERATORS],
  ['hours_in_stage', 'number', 'HOURS_IN_STAGE', null, NUMERIC_OPERATORS],
  ['reason_id', 'multiSelect', 'REASON', 'reasons'],
  ['origin', 'multiSelect', 'ORIGIN', 'origins'],
  [
    'contact_has_open_card',
    'booleanSelect',
    'CONTACT_HAS_OPEN_CARD',
    null,
    BOOLEAN_OPERATORS,
  ],
];

export const NUMERIC_CONDITIONS = new Set([
  'stage_id',
  'previous_stage_id',
  'assignee_id',
  'inbox_id',
  'total_value',
  'hours_in_stage',
  'reason_id',
]);

export const buildFilterTypes = ({ t, optionsFor, operatorsFor }) =>
  CONDITIONS.map(([attributeKey, inputType, labelKey, optionsKey, ops]) => {
    const label = t(`KANBAN.AUTOMATIONS.FORM.CONDITIONS.${labelKey}`);
    return {
      attributeKey,
      value: attributeKey,
      label,
      attributeName: label,
      inputType,
      options: optionsKey ? optionsFor(optionsKey) : [],
      filterOperators: operatorsFor(ops || SELECT_OPERATORS),
    };
  });

export const DEFAULT_CONDITION_KEY = 'stage_id';
