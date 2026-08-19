import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';

export function useKanbanCardActions({
  cardActionKey,
  cardPendingRemoval,
  endAction,
  findCardStageId,
  flushPendingRealtimeKanbanEvents,
  getErrorMessage,
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
  suppressNextCardClick,
  t,
  toIso8601,
  useAlert,
}) {
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
    // position is omitted and the backend appends the card to the real end.
    // A collapsed column loads no cards at all, so it always appends.
    const isLastLoadedSlot = targetIndex === stage.cards.length - 1;
    const appendsToStageEnd =
      appendToStageEnd || (isLastLoadedSlot && !!stage.pagination?.hasMore);
    const destinationPosition = appendsToStageEnd ? undefined : targetIndex + 1;
    const stageChanged = card.kanbanStageId !== stage.id;
    const positionChanged =
      appendsToStageEnd || card.position !== destinationPosition;
    if (!stageChanged && !positionChanged) return;

    const actionKey = cardActionKey(card);
    if (isActionActive(actionKey)) return;

    isPersistingCardDrag.value = true;
    startAction(actionKey);
    const payload = {
      card: {
        kanban_stage_id: stage.id,
        ...(appendsToStageEnd ? {} : { position: destinationPosition }),
      },
    };

    try {
      await KanbanBoardsAPI.reorderCardById(
        selectedBoard.value.id,
        card.id,
        payload
      );
      await refreshStageFirstPages([card.kanbanStageId, stage.id]);
    } catch (error) {
      let message = getErrorMessage(
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
      await refreshStageFirstPages([card.kanbanStageId, stage.id]);
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

  const updateCardPriority = async (card, priorityValue) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.updateCardDetailsById(
        selectedBoard.value.id,
        card.id,
        { priority: priorityValue || null }
      );
      patchVisibleCard({ id: card.id, card_priority: priorityValue });
    } catch (error) {
      showActionError(error, t('KANBAN.CARD.PRIORITY_UPDATE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

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

  const assignAgent = async (card, userId) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    const numericUserId = Number(userId);
    const currentAssigneeIds = (card.assignees || []).map(assignee =>
      Number(assignee.id)
    );
    const nextAssigneeIds = currentAssigneeIds.includes(numericUserId)
      ? currentAssigneeIds.filter(id => id !== numericUserId)
      : [...currentAssigneeIds, numericUserId];

    startAction(actionKey);

    try {
      const response = await KanbanBoardsAPI.updateCardAssignees(
        selectedBoard.value.id,
        card.id,
        nextAssigneeIds
      );
      patchVisibleCard({
        id: card.id,
        kanbanStageId: card.kanbanStageId,
        assignees: normalizePayload(response.data.payload),
      });
      useAlert(t('KANBAN.CARD.ASSIGN_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.CARD.ASSIGN_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const updateCardDueDate = async (card, dueDate) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    const dueAt = toIso8601(dueDate);
    startAction(actionKey);

    try {
      await KanbanBoardsAPI.updateCardDetailsById(
        selectedBoard.value.id,
        card.id,
        { due_at: dueAt }
      );
      patchVisibleCard({
        id: card.id,
        kanbanStageId: card.kanbanStageId,
        due_at: dueAt,
      });
      useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.CARD.DUE_DATE_UPDATE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const updateCardLabels = async (card, labelTitles) => {
    const actionKey = cardActionKey(card);
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;

    startAction(actionKey);

    try {
      const response = await KanbanBoardsAPI.updateCardLabels(
        selectedBoard.value.id,
        card.id,
        labelTitles
      );
      patchVisibleCard({
        id: card.id,
        kanbanStageId: card.kanbanStageId,
        labels: normalizePayload(response.data.payload),
      });
    } catch (error) {
      showActionError(error, t('CONTACT_PANEL.LABELS.CONVERSATION.ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

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
      useAlert(
        getCardStatusChangeErrorMessage(error, { reopen, t, getErrorMessage })
      );
    } finally {
      endAction(actionKey);
    }
  };

  return {
    assignAgent,
    closeRemoveCardConfirmation,
    confirmRemoveCard,
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
