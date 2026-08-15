import { computed } from 'vue';

export function useKanbanStageOrder({ stages, wonStageId, lostStageId }) {
  const terminalStageIds = computed(() =>
    [wonStageId.value, lostStageId.value].filter(Boolean)
  );

  const isTerminalStage = stage => terminalStageIds.value.includes(stage?.id);
  const isWonStage = stage =>
    Boolean(stage?.id) && stage.id === wonStageId.value;
  const isLostStage = stage =>
    Boolean(stage?.id) && stage.id === lostStageId.value;

  const stageTone = stage => {
    if (isWonStage(stage)) return 'won';
    if (isLostStage(stage)) return 'lost';
    return null;
  };

  const regularStages = computed(() =>
    stages.value.filter(stage => !isTerminalStage(stage))
  );

  // Kept in won-then-lost order rather than board order so the UI always
  // lists the terminal stages the same way.
  const terminalStages = computed(() =>
    [wonStageId.value, lostStageId.value]
      .map(id => stages.value.find(stage => stage.id === id))
      .filter(Boolean)
  );

  const regularStageCount = computed(() => regularStages.value.length);

  const canMoveStage = event => {
    const draggedStage = event?.draggedContext?.element;
    if (isTerminalStage(draggedStage)) return false;

    const futureIndex = event?.draggedContext?.futureIndex;
    if (futureIndex === undefined) return true;

    return futureIndex < regularStageCount.value;
  };

  return {
    terminalStageIds,
    isTerminalStage,
    isWonStage,
    isLostStage,
    stageTone,
    regularStages,
    terminalStages,
    canMoveStage,
  };
}
