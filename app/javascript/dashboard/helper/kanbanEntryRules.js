export const NONE_VALUE = 'none';

// The four conversation attributes an entry rule can read, each with the operators that
// make sense for it. Inbox is absent on purpose: it is the rule's scope, not a condition.
export const ENTRY_RULE_FIELDS = [
  {
    key: 'labels',
    operators: ['includes_any', 'includes_all', 'not_includes'],
  },
  { key: 'assignee_id', operators: ['is_one_of', 'is_not_one_of'] },
  { key: 'team_id', operators: ['is_one_of', 'is_not_one_of'] },
  { key: 'priority', operators: ['is_one_of', 'is_not_one_of'] },
];

export const emptyConditionForm = () =>
  Object.fromEntries(
    ENTRY_RULE_FIELDS.map(field => [
      field.key,
      { operator: field.operators[0], values: [] },
    ])
  );

// A field with no values is left out entirely: an empty selection means "do not filter on
// this", not "match nothing".
export const buildConditions = conditionForm =>
  ENTRY_RULE_FIELDS.filter(
    field => conditionForm[field.key]?.values?.length
  ).map(field => ({
    attribute_key: field.key,
    filter_operator: conditionForm[field.key].operator,
    values: conditionForm[field.key].values.map(String),
  }));

export const conditionsToForm = (conditions = []) => {
  const form = emptyConditionForm();
  conditions.forEach(condition => {
    const key = condition.attributeKey ?? condition.attribute_key;
    if (!form[key]) return;
    form[key] = {
      operator: condition.filterOperator ?? condition.filter_operator,
      values: (condition.values || []).map(String),
    };
  });
  return form;
};

const inboxReach = rule =>
  rule.allInboxes ? Infinity : (rule.inboxIds || []).length;

// Widening is what earns the retroactive-import offer: reaching more inboxes, or dropping
// a condition. Narrowing a rule has no history to go back for.
export const isRuleWiderThan = (rule, previousRule) => {
  if (inboxReach(rule) > inboxReach(previousRule)) return true;

  return (
    (rule.conditions || []).length < (previousRule.conditions || []).length
  );
};
