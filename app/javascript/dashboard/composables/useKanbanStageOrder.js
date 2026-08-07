import { computed } from 'vue';

export function useKanbanStageOrder({ stages, wonStageId, lostStageId }) {
  const terminalStageIds = computed(() =>
    [wonStageId.value, lostStageId.value].filter(Boolean)
  );

  const isTerminalStage = stage => terminalStageIds.value.includes(stage?.id);

  const regularStageCount = computed(
    () => stages.value.filter(stage => !isTerminalStage(stage)).length
  );

  const canMoveStage = event => {
    const draggedStage = event?.draggedContext?.element;
    if (isTerminalStage(draggedStage)) return false;

    const futureIndex = event?.draggedContext?.futureIndex;
    if (futureIndex === undefined) return true;

    return futureIndex < regularStageCount.value;
  };

  return { terminalStageIds, isTerminalStage, canMoveStage };
}
