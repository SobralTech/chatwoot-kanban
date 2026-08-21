import { NUMERIC_CONDITIONS } from './ruleConditionTypes';

// The filter widget wants option objects ({ id, name }); the API wants bare scalars.
// These two functions are the translation in each direction.

const idOf = value =>
  value && typeof value === 'object' && 'id' in value ? value.id : value;

const asArray = values => (Array.isArray(values) ? values : [values]);

const toOption = (filter, value) => {
  const valueId = idOf(value);
  return (
    filter.options.find(option => String(option.id) === String(valueId)) ||
    (value && typeof value === 'object'
      ? value
      : { id: valueId, name: String(valueId) })
  );
};

// Mutates in place: the condition object is the one bound to the row component.
export const toWidgetValues = (
  condition,
  filter,
  { trueLabel, falseLabel }
) => {
  const values = asArray(condition.values);

  if (filter?.inputType === 'multiSelect') {
    const operandless = ['is_present', 'is_not_present'].includes(
      condition.filter_operator
    );
    condition.values = operandless
      ? []
      : values.map(value => toOption(filter, value)).filter(Boolean);
    return;
  }

  if (filter?.inputType === 'booleanSelect') {
    const value = idOf(values[0]);
    if (value === undefined || value === null || value === '') {
      condition.values = {};
      return;
    }

    const isTrue = value === true || value === 'true';
    condition.values = { id: isTrue, name: isTrue ? trueLabel : falseLabel };
    return;
  }

  if (filter?.inputType === 'number') condition.values = values[0] ?? '';
};

export const toApiValues = condition => {
  const values = asArray(condition.values)
    .map(idOf)
    .filter(value => value !== undefined && value !== null && value !== '');

  if (condition.attribute_key === 'contact_has_open_card') {
    return values.map(value => value === true || value === 'true');
  }
  if (NUMERIC_CONDITIONS.has(condition.attribute_key)) {
    return values.map(Number);
  }
  return values;
};
