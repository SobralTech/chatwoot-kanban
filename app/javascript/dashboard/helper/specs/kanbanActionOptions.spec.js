import {
  getKanbanAgentOptionsByBoard,
  getKanbanStageOptions,
} from '../kanbanActionOptions';

const boards = [
  {
    id: 1,
    name: 'Sales',
    wonStageId: 4,
    lostStageId: 5,
    lostReasonRequired: false,
    visibilityMode: 'all_agents',
    stagesSummary: [
      { id: 2, name: 'Prospecting' },
      { id: 4, name: 'Won' },
      { id: 5, name: 'Lost' },
    ],
    visibleUsers: [],
  },
  {
    id: 3,
    name: 'Support',
    wonStageId: null,
    lostStageId: null,
    lostReasonRequired: false,
    visibilityMode: 'selected_agents',
    stagesSummary: [{ id: 6, name: 'Triage' }],
    visibleUsers: [{ id: 9, name: 'Visible agent' }],
  },
];

describe('kanban action options', () => {
  it('formats regular stages as funnel and stage options', () => {
    expect(getKanbanStageOptions(boards, 'add_to_kanban_board')).toEqual([
      { id: '1:2', name: 'Sales › Prospecting' },
      { id: '3:6', name: 'Support › Triage' },
    ]);
  });

  it('uses visible board members for selected-agent boards', () => {
    expect(
      getKanbanAgentOptionsByBoard(boards, [{ id: 8, name: 'Account agent' }])
    ).toEqual({
      1: [{ id: 8, name: 'Account agent' }],
      3: [{ id: 9, name: 'Visible agent' }],
    });
  });
});
