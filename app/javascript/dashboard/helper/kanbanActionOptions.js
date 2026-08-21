export const KANBAN_STAGE_ACTIONS = ['add_to_kanban_board', 'move_kanban_card'];

export const KANBAN_AGENT_ACTIONS = ['assign_kanban_card'];

export const KANBAN_ACTIONS = [
  ...KANBAN_STAGE_ACTIONS,
  ...KANBAN_AGENT_ACTIONS,
];

const stagesOf = board => board.stagesSummary || [];

const isTerminal = (board, stage) =>
  stage.id === board.wonStageId || stage.id === board.lostStageId;

// A stage option carries both ids in one value, because the action form has no
// dependent selects. `parseBoardStageId` is the other half of this contract.
const isSelectable = (board, stage, actionName) => {
  if (isTerminal(board, stage)) {
    return (
      actionName === 'move_kanban_card' &&
      stage.id === board.lostStageId &&
      !board.lostReasonRequired
    );
  }
  return true;
};

export const getKanbanStageOptions = (boards, actionName) =>
  boards.flatMap(board =>
    stagesOf(board)
      .filter(stage => isSelectable(board, stage, actionName))
      .map(stage => ({
        id: `${board.id}:${stage.id}`,
        name: `${board.name} › ${stage.name}`,
      }))
  );

// Each board carries the agents assignable on it, so the action input stays a plain
// list of options instead of a differently shaped object.
export const getKanbanBoardOptions = (boards, agents) =>
  boards.map(board => ({
    id: board.id,
    name: board.name,
    agents: (board.visibilityMode === 'selected_agents'
      ? board.visibleUsers || []
      : agents
    ).map(user => ({ id: user.id, name: user.name })),
  }));

export const kanbanDropdownValues = (actionName, boards, agents) => {
  if (KANBAN_STAGE_ACTIONS.includes(actionName)) {
    return getKanbanStageOptions(boards, actionName);
  }
  if (KANBAN_AGENT_ACTIONS.includes(actionName)) {
    return getKanbanBoardOptions(boards, agents);
  }
  return null;
};

export const parseBoardStageId = value => {
  const [kanbanBoardId, kanbanStageId] = String(value || '').split(':');
  return {
    kanbanBoardId: Number(kanbanBoardId),
    kanbanStageId: Number(kanbanStageId),
  };
};
