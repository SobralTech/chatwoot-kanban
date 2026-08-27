import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useKanbanCardFields } from 'dashboard/composables/useKanbanCardFields';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';

export function useKanbanCardActions({
  applyCardStageMove,
  cardActionKey,
  boards,
  cardPendingRemoval,
  endAction,
  findCardStageId,
  flushPendingRealtimeKanbanEvents,
  hasActiveFilters,
  isActionActive,
  isCardDragging,
  hasCardDragChanged,
  isLostReasonRequiredError,
  isPersistingCardDrag,
  isTerminalStage,
  normalizePayload,
  patchVisibleCard,
  refreshStageFirstPage,
  refreshStageFirstPages,
  selectedBoard,
  showActionError,
  showRemoveCardConfirmation,
  stages,
  startAction,
  startBoardAutoScroll,
  stopBoardAutoScroll,
  suppressCardReorderEcho,
  suppressNextCardClick,
  t,
  useAlert,
}) {
  const cardFields = useKanbanCardFields({
    t,
    boardIdFor: () => selectedBoard.value?.id,
    // The board holds its cards inside paginated stage lists rather than in one
    // object, so a field update lands through the same patch realtime uses.
    patchCard: (card, partial) =>
      patchVisibleCard({
        id: card.id,
        kanbanStageId: card.kanbanStageId,
        ...partial,
      }),
  });

  // Field updates keep going through the board's own busy tracking so a card
  // still greys out and refuses a second action while one is in flight.
  const withCardAction = async (card, run) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return false;

    startAction(actionKey);
    try {
      return await run();
    } finally {
      endAction(actionKey);
    }
  };

  const onCardDragStart = () => {
    isCardDragging.value = true;
    hasCardDragChanged.value = false;
    startBoardAutoScroll();
  };

  const onCardDragChange = async (
    stage,
    event,
    { appendToStageEnd = false } = {}
  ) => {
    if (event?.added || event?.moved || event?.removed) {
      hasCardDragChanged.value = true;
    }

    const card = event?.added?.element || event?.moved?.element;
    const targetIndex = event?.added?.newIndex ?? event?.moved?.newIndex;
    if (
      !selectedBoard.value?.id ||
      !stage?.id ||
      !card ||
      targetIndex === undefined ||
      isPersistingCardDrag.value
    ) {
      return;
    }

    // Dropping on the last loaded slot while more cards exist beyond the
    // page means the true end of the stage isn't known locally, so the
    // anchor is omitted and the backend appends the card to the real end.
    // A collapsed column loads no cards at all, so it always appends.
    const isLastLoadedSlot = targetIndex === stage.cards.length - 1;
    const appendsToStageEnd =
      appendToStageEnd || (isLastLoadedSlot && !!stage.pagination?.hasMore);
    const stageChanged = card.kanbanStageId !== stage.id;
    // Stored positions are sparse, and under filters the visible list is only a
    // subset, so a local index says nothing about where the card actually sits:
    // the drag event is what signals a move.
    const positionChanged =
      stageChanged || event?.moved?.oldIndex !== event?.moved?.newIndex;
    if (!positionChanged) return;

    const actionKey = cardActionKey(card);
    if (isActionActive(actionKey)) return;

    isPersistingCardDrag.value = true;
    startAction(actionKey);
    // A null anchor means the card was dropped at the top of the stage; the
    // backend places it between the anchor and whatever follows it.
    const anchorCard = targetIndex > 0 ? stage.cards[targetIndex - 1] : null;
    const cardPayload = { kanban_stage_id: stage.id };
    if (hasActiveFilters.value || !appendsToStageEnd) {
      cardPayload.after_card_id = anchorCard?.id ?? null;
    }
    const payload = { card: cardPayload };
    const sourceStageId = card.kanbanStageId;
    // Registered before the request so the broadcast, which the server fires on its own
    // schedule, cannot beat it back here and refresh the columns anyway.
    suppressCardReorderEcho(card.id);

    try {
      const response = await KanbanBoardsAPI.reorderCardById(
        selectedBoard.value.id,
        card.id,
        payload
      );
      // The card is already where it was dropped - the drag moved it between the stage
      // arrays before the request went out - so only the counters and the card's own
      // stage fields are left to settle. Refetching both columns to redraw the same
      // cards is what turned a request of a few hundred milliseconds into a board reload.
      applyCardStageMove(card, sourceStageId, stage.id);
      patchVisibleCard(response.data);
    } catch (error) {
      let message = apiErrorMessage(
        error,
        t('KANBAN.ACTIONS.REORDER_CARD_ERROR')
      );
      if (isLostReasonRequiredError(error)) {
        message = t('KANBAN.ACTIONS.DRAG_LOST_REASON_REQUIRED');
      }
      if (isDirectWonLostTransitionError(error)) {
        message = t(
          'KANBAN.ACTIONS.DRAG_DIRECT_WON_LOST_TRANSITION_NOT_ALLOWED'
        );
      }

      useAlert(message);
      // The move stays on screen until the server's answer replaces it, so a rejected
      // drop visibly snaps back instead of silently disagreeing with the board.
      await refreshStageFirstPages([sourceStageId, stage.id]);
    } finally {
      isPersistingCardDrag.value = false;
      endAction(actionKey);
    }
  };

  const onCardDragEnd = () => {
    stopBoardAutoScroll();
    if (isCardDragging.value || hasCardDragChanged.value) {
      suppressNextCardClick.value = true;
      window.setTimeout(() => {
        suppressNextCardClick.value = false;
      }, 0);
    }

    isCardDragging.value = false;
    hasCardDragChanged.value = false;
    flushPendingRealtimeKanbanEvents();
  };

  const openRemoveCardConfirmation = card => {
    cardPendingRemoval.value = card;
    showRemoveCardConfirmation.value = true;
  };

  const closeRemoveCardConfirmation = () => {
    showRemoveCardConfirmation.value = false;
    cardPendingRemoval.value = null;
  };

  const removeCard = async card => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.deleteCardById(selectedBoard.value.id, card.id);
      await refreshStageFirstPage(findCardStageId(card));
      useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const confirmRemoveCard = async () => {
    const card = cardPendingRemoval.value;
    closeRemoveCardConfirmation();

    if (!card) return;

    await removeCard(card);
  };

  const updateCardPriority = (card, priorityValue) =>
    withCardAction(card, () =>
      // The compact card spends `priority` on the conversation's priority, so
      // the card's own value has to land on its own key.
      cardFields.updateDetail(card, 'priority', priorityValue || '', {
        patchKey: 'cardPriority',
      })
    );

  const moveCardToStage = async (card, targetStageId) => {
    const targetStage = stages.value.find(
      stage => Number(stage.id) === Number(targetStageId)
    );
    const actionKey = cardActionKey(card);
    if (
      !selectedBoard.value?.id ||
      !targetStage ||
      isTerminalStage(targetStage) ||
      isActionActive(actionKey)
    ) {
      return false;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.reorderCardById(selectedBoard.value.id, card.id, {
        card: {
          kanban_stage_id: targetStage.id,
          after_card_id: null,
        },
      });
      await refreshStageFirstPages([card.kanbanStageId, targetStage.id]);
      useAlert(t('KANBAN.CARD.MOVE_SUCCESS'));
      return true;
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
      return false;
    } finally {
      endAction(actionKey);
    }
  };
  const moveCardToBoard = async (card, { boardId, stageId } = {}) => {
    const targetBoard = (boards?.value || []).find(
      board => Number(board.id) === Number(boardId)
    );
    const actionKey = cardActionKey(card);
    if (
      !selectedBoard.value?.id ||
      !targetBoard ||
      Number(targetBoard.id) === Number(selectedBoard.value.id) ||
      !stageId ||
      isActionActive(actionKey)
    ) {
      return false;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.moveCardToBoard(selectedBoard.value.id, card.id, {
        target_kanban_board_id: targetBoard.id,
        kanban_stage_id: stageId,
      });
      await refreshStageFirstPages([card.kanbanStageId]);
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_SUCCESS', { board: targetBoard.name })
      );
      return true;
    } catch (error) {
      const errorCode = error?.response?.data?.error;
      let errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR');
      if (errorCode === 'card_already_in_target_board') {
        errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR_DUPLICATE', {
          board: targetBoard.name,
        });
      } else if (errorCode === 'inbox_not_allowed') {
        errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR_INBOX', {
          board: targetBoard.name,
        });
      }
      useAlert(errorMessage);
      return false;
    } finally {
      endAction(actionKey);
    }
  };

  const assignAgent = async (card, userId) => {
    const numericUserId = Number(userId);
    const currentAssigneeIds = (card.assignees || []).map(assignee =>
      Number(assignee.id)
    );
    const nextAssigneeIds = currentAssigneeIds.includes(numericUserId)
      ? currentAssigneeIds.filter(id => id !== numericUserId)
      : [...currentAssigneeIds, numericUserId];

    const assigned = await withCardAction(card, () =>
      cardFields.updateAssignees(card, nextAssigneeIds)
    );
    if (assigned) useAlert(t('KANBAN.CARD.ASSIGN_SUCCESS'));
  };

  const updateCardDueDate = async (card, dueDate) => {
    const updated = await withCardAction(card, () =>
      cardFields.updateDetail(card, 'dueAt', dueDate)
    );
    if (updated) useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_SUCCESS'));
  };

  const updateCardLabels = (card, labelTitles) =>
    withCardAction(card, () => cardFields.updateLabels(card, labelTitles));

  const onChangeCardStatus = async (
    card,
    { targetStageId, reasonId, reopen }
  ) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    startAction(actionKey);

    try {
      const response = reopen
        ? await KanbanBoardsAPI.reopenCardById(selectedBoard.value.id, card.id)
        : await KanbanBoardsAPI.updateCardById(
            selectedBoard.value.id,
            card.id,
            {
              card: {
                kanban_stage_id: targetStageId,
                kanban_reason_id: reasonId || null,
              },
            }
          );
      const updatedCard = normalizePayload(response.data);
      const nextStageId = updatedCard.kanbanStageId || targetStageId;
      await refreshStageFirstPages([card.kanbanStageId, nextStageId]);
      useAlert(
        t(
          reopen
            ? 'KANBAN.CARD.STATUS.REOPEN_SUCCESS'
            : 'KANBAN.CARD.STATUS.UPDATE_SUCCESS'
        )
      );
    } catch (error) {
      useAlert(getCardStatusChangeErrorMessage(error, { reopen, t }));
    } finally {
      endAction(actionKey);
    }
  };

  return {
    assignAgent,
    closeRemoveCardConfirmation,
    confirmRemoveCard,
    moveCardToBoard,
    moveCardToStage,
    onCardDragChange,
    onCardDragEnd,
    onCardDragStart,
    onChangeCardStatus,
    openRemoveCardConfirmation,
    removeCard,
    updateCardDueDate,
    updateCardLabels,
    updateCardPriority,
  };
}
