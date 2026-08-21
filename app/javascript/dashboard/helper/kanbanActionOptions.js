export const KANBAN_STAGE_ACTIONS = ['add_to_kanban_board', 'move_kanban_card'];

export const KANBAN_AGENT_ACTIONS = ['assign_kanban_card'];

const boardStageId = (boardId, stageId) => `${boardId}:${stageId}`;

const boardId = board => board.id;
const stageId = stage => stage.id;

const boardStages = board => board.stagesSummary || [];

const isWonStage = (board, stage) => stageId(stage) === board.wonStageId;
const isLostStage = (board, stage) => stageId(stage) === board.lostStageId;

export const getKanbanStageOptions = (boards, actionName) => {
  return boards.flatMap(board =>
    boardStages(board)
      .filter(stage => {
        if (actionName === 'add_to_kanban_board') {
          return !isWonStage(board, stage) && !isLostStage(board, stage);
        }

        if (actionName === 'move_kanban_card') {
          return (
            !isWonStage(board, stage) &&
            (!isLostStage(board, stage) || !board.lostReasonRequired)
          );
        }

        return false;
      })
      .map(stage => ({
        id: boardStageId(boardId(board), stageId(stage)),
        name: `${board.name} › ${stage.name}`,
      }))
  );
};

export const getKanbanBoardOptions = boards =>
  boards.map(board => ({ id: boardId(board), name: board.name }));

export const getKanbanAgentOptionsByBoard = (boards, agents) =>
  boards.reduce((options, board) => {
    const users =
      board.visibilityMode === 'selected_agents'
        ? board.visibleUsers || []
        : agents;

    options[boardId(board)] = users.map(user => ({
      id: user.id,
      name: user.name,
    }));
    return options;
  }, {});

export const parseBoardStageId = value => {
  const [kanbanBoardId, kanbanStageId] = String(value || '').split(':');
  return {
    kanbanBoardId: Number(kanbanBoardId),
    kanbanStageId: Number(kanbanStageId),
  };
};
