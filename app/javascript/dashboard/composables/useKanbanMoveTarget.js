import { computed, ref, unref } from 'vue';
import { useI18n } from 'vue-i18n';

// The board a card sits on comes from the show endpoint, which sends allowedInboxIds;
// every other board comes from the index, which sends the inboxes themselves.
const boardAllowedInboxIds = board =>
  (
    board.allowedInboxIds ??
    board.allowedInboxes?.map(allowedInbox => allowedInbox.id) ??
    []
  ).map(Number);

// Sending cards to another funnel always means picking a funnel and then one of its
// regular stages, whether it is one card, a selection or a whole stage being emptied.
// `inboxId` narrows the funnels to the ones that accept it, which only a single card
// can know; `excludeStageId` hides the stage the cards are already in.
export function useKanbanMoveTarget({
  board = null,
  boards,
  currentBoardId,
  excludeStageId = null,
  inboxId = null,
  lostStageId,
  stages,
  wonStageId,
}) {
  const { t } = useI18n();
  const pickedBoardId = ref(null);

  const sourceBoard = computed(() => {
    const currentBoard = unref(board);
    if (currentBoard?.id) return currentBoard;

    return (
      unref(boards).find(item => Number(item.id) === unref(currentBoardId)) ||
      {}
    );
  });

  const acceptsInbox = targetBoard => {
    const requiredInboxId = unref(inboxId);
    if (!requiredInboxId) return true;

    return (
      targetBoard.inboxScopeMode !== 'selected_inboxes' ||
      boardAllowedInboxIds(targetBoard).includes(Number(requiredInboxId))
    );
  };

  // A card opened from outside the board page has no funnel list to offer, so it falls
  // back to the one funnel it already knows.
  const availableBoards = computed(() => {
    const knownBoards = unref(boards).length
      ? unref(boards)
      : [sourceBoard.value];

    return knownBoards
      .filter(item => item?.id && item.active !== false && acceptsInbox(item))
      .slice()
      .sort((firstBoard, secondBoard) => {
        const firstIsCurrent = Number(firstBoard.id) === unref(currentBoardId);
        const secondIsCurrent =
          Number(secondBoard.id) === unref(currentBoardId);
        if (firstIsCurrent !== secondIsCurrent) return firstIsCurrent ? -1 : 1;

        return (
          Number(firstBoard.position ?? 0) - Number(secondBoard.position ?? 0)
        );
      });
  });

  const boardOptions = computed(() =>
    availableBoards.value.map(item => ({
      value: item.id,
      label:
        Number(item.id) === unref(currentBoardId)
          ? t('KANBAN.CARD.MOVE_CURRENT_BOARD', { name: item.name })
          : item.name,
    }))
  );

  // Nothing picked yet means the funnel the cards already sit on.
  const boardId = computed({
    get: () => pickedBoardId.value ?? unref(currentBoardId),
    set: value => {
      pickedBoardId.value = value;
    },
  });

  const selectedBoard = computed(
    () =>
      availableBoards.value.find(
        item => Number(item.id) === Number(boardId.value)
      ) || sourceBoard.value
  );

  const isCurrentBoard = computed(
    () => Number(boardId.value) === Number(unref(currentBoardId))
  );

  // Only the current funnel is loaded with its full stage list; every other one is known
  // through the summary the index endpoint sends.
  const targetStages = computed(() => {
    const targetBoard = selectedBoard.value;
    const [terminalWonStageId, terminalLostStageId] = isCurrentBoard.value
      ? [unref(wonStageId), unref(lostStageId)]
      : [targetBoard.wonStageId, targetBoard.lostStageId];
    const skippedStageIds = [
      terminalWonStageId,
      terminalLostStageId,
      isCurrentBoard.value ? unref(excludeStageId) : null,
    ]
      .filter(Boolean)
      .map(Number);

    return (
      isCurrentBoard.value ? unref(stages) : targetBoard.stagesSummary || []
    ).filter(stage => !skippedStageIds.includes(Number(stage.id)));
  });

  const reset = () => {
    pickedBoardId.value = null;
  };

  return {
    boardId,
    boardOptions,
    isCurrentBoard,
    reset,
    selectedBoard,
    sourceBoard,
    targetStages,
  };
}
