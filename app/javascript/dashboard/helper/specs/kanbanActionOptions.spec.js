import {
  getKanbanBoardOptions,
  getKanbanStageOptions,
  kanbanDropdownValues,
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

  it('offers the lost stage to a move only when the board needs no reason', () => {
    expect(getKanbanStageOptions(boards, 'move_kanban_card')).toEqual([
      { id: '1:2', name: 'Sales › Prospecting' },
      { id: '1:5', name: 'Sales › Lost' },
      { id: '3:6', name: 'Support › Triage' },
    ]);
  });

  it('carries each board its own assignable agents', () => {
    expect(
      getKanbanBoardOptions(boards, [{ id: 8, name: 'Account agent' }])
    ).toEqual([
      { id: 1, name: 'Sales', agents: [{ id: 8, name: 'Account agent' }] },
      { id: 3, name: 'Support', agents: [{ id: 9, name: 'Visible agent' }] },
    ]);
  });

  it('returns null for actions that are not Kanban ones', () => {
    expect(kanbanDropdownValues('add_label', boards, [])).toBeNull();
  });
});
