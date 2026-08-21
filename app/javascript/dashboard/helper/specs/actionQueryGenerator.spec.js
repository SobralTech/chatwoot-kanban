import actionQueryGenerator from '../actionQueryGenerator';

const testData = [
  {
    action_name: 'add_label',
    action_params: [{ id: 'testlabel', name: 'testlabel' }],
  },
  {
    action_name: 'assign_team',
    action_params: [
      {
        id: 1,
        name: 'sales team',
        description: 'This is our internal sales team',
        allow_auto_assign: true,
        account_id: 1,
        is_member: true,
      },
    ],
  },
];

const finalResult = [
  {
    action_name: 'add_label',
    action_params: ['testlabel'],
  },
  {
    action_name: 'assign_team',
    action_params: [1],
  },
];

describe('#actionQueryGenerator', () => {
  it('returns the correct format of filter query', () => {
    expect(actionQueryGenerator(testData)).toEqual(finalResult);
    expect(
      actionQueryGenerator(testData).every(i => Array.isArray(i.action_params))
    ).toBe(true);
  });

  it('preserves Kanban action objects inside action_params', () => {
    const kanbanAction = {
      action_name: 'add_to_kanban_board',
      action_params: [{ kanban_board_id: 7, kanban_stage_id: 11 }],
    };

    expect(actionQueryGenerator([kanbanAction])).toEqual([kanbanAction]);
  });
});
