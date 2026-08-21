import {
  toApiValues,
  toWidgetValues,
} from '../automations/ruleConditionValues';

const labels = { trueLabel: 'True', falseLabel: 'False' };

describe('rule condition values', () => {
  it('matches saved ids back to their option objects', () => {
    const condition = {
      attribute_key: 'stage_id',
      filter_operator: 'equal_to',
      values: [7],
    };
    const filter = {
      inputType: 'multiSelect',
      options: [{ id: 7, name: 'Negotiation' }],
    };

    toWidgetValues(condition, filter, labels);

    expect(condition.values).toEqual([{ id: 7, name: 'Negotiation' }]);
  });

  it('drops operands for operators that take none', () => {
    const condition = {
      attribute_key: 'labels',
      filter_operator: 'is_not_present',
      values: [{ id: 'vip', name: 'vip' }],
    };

    toWidgetValues(
      condition,
      { inputType: 'multiSelect', options: [] },
      labels
    );

    expect(condition.values).toEqual([]);
  });

  it('numbers the id conditions on the way out', () => {
    expect(
      toApiValues({ attribute_key: 'stage_id', values: [{ id: '7' }] })
    ).toEqual([7]);
  });

  it('keeps a boolean condition boolean', () => {
    expect(
      toApiValues({
        attribute_key: 'contact_has_open_card',
        values: { id: true, name: 'True' },
      })
    ).toEqual([true]);
  });

  it('drops blanks rather than sending them', () => {
    expect(
      toApiValues({ attribute_key: 'origin', values: ['manual', '', null] })
    ).toEqual(['manual']);
  });
});
