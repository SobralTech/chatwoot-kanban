import { getKanbanMoveConsequences } from '../kanbanMoveConsequences';

const sourceBoard = {
  id: 1,
  name: 'Sales',
  wonStageId: 10,
  lostStageId: 20,
  customFields: [
    { key: 'segment', fieldType: 'text', multiple: false },
    { key: 'region', fieldType: 'text', multiple: false },
    { key: 'products', fieldType: 'list', multiple: true },
  ],
};

const targetBoard = {
  id: 2,
  name: 'Support',
  customFields: [{ key: 'segment', fieldType: 'text', multiple: false }],
};

describe('getKanbanMoveConsequences', () => {
  it('describes terminal status, reason and discarded fields', () => {
    const consequences = getKanbanMoveConsequences({
      card: {
        kanbanStageId: 20,
        kanbanReasonId: 9,
        customFieldKeys: ['segment', 'region', 'products'],
      },
      sourceBoard,
      targetBoard,
      reasons: [{ id: 9, title: 'Budget rejected' }],
    });

    expect(consequences).toEqual([
      { key: 'MOVE_CONFIRM_REOPEN', params: {} },
      {
        key: 'MOVE_CONFIRM_REASON',
        params: { reason: 'Budget rejected' },
      },
      {
        key: 'MOVE_CONFIRM_FIELDS',
        params: {
          count: 2,
          total: 3,
          board: 'Support',
          keys: 'region, products',
        },
      },
    ]);
  });

  it('describes when a terminal recurrence reference leaves the board', () => {
    expect(
      getKanbanMoveConsequences({
        card: { kanbanStageId: 20 },
        sourceBoard: { ...sourceBoard, lostRecurrenceEnabled: true },
        targetBoard,
      })
    ).toContainEqual({
      key: 'MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES',
      params: { board: 'Sales' },
    });
  });

  it('describes possible recurrence recreation from an open stage', () => {
    expect(
      getKanbanMoveConsequences({
        card: { kanbanStageId: 1 },
        sourceBoard: { ...sourceBoard, wonRecurrenceEnabled: true },
        targetBoard,
      })
    ).toContainEqual({
      key: 'MOVE_CONFIRM_RECURRENCE_MAY_RECREATE',
      params: { board: 'Sales' },
    });
  });

  it('returns no consequences when all data is compatible', () => {
    expect(
      getKanbanMoveConsequences({
        card: { kanbanStageId: 1, customFieldKeys: ['segment'] },
        sourceBoard,
        targetBoard: {
          ...targetBoard,
          customFields: [...sourceBoard.customFields],
        },
      })
    ).toEqual([]);
  });
});
