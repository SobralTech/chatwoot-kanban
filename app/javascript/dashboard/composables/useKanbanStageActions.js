import { nextTick } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

export function useKanbanStageActions({
  boardScrollContainer,
  defaultStageColor,
  editingStageId,
  endAction,
  isActionActive,
  isCreatingStage,
  isCreatingStageDraft,
  isTerminalStage,
  newStageColor,
  newStageName,
  newStageNameInput,
  normalizePayload,
  pendingScrollToStageId,
  refreshSelectedBoard,
  refreshStageFirstPages,
  selectedBoard,
  showRemoveStageCardsConfirmation,
  showRemoveStageConfirmation,
  stageCardsPendingRemoval,
  stagePendingRemoval,
  showActionError,
  stageColors,
  stageNames,
  stageNameInputs,
  stages,
  startAction,
  stopBoardAutoScroll,
  store,
  t,
  useAlert,
}) {
  const setStageNameInput = (stageId, element) => {
    if (element) {
      stageNameInputs.set(stageId, element);
      return;
    }

    stageNameInputs.delete(stageId);
  };

  const updateStageNameDraft = ({ stageId, value }) => {
    stageNames.value = {
      ...stageNames.value,
      [stageId]: value,
    };
  };

  const updateStageColorDraft = ({ stageId, value }) => {
    stageColors.value = {
      ...stageColors.value,
      [stageId]: value,
    };
  };

  const startEditingStage = stage => {
    editingStageId.value = stage.id;
    stageNames.value = {
      ...stageNames.value,
      [stage.id]: stage.name,
    };
    stageColors.value = {
      ...stageColors.value,
      [stage.id]: stage.color,
    };
    nextTick(() => stageNameInputs.get(stage.id)?.focus());
  };

  const openStageDraft = () => {
    isCreatingStageDraft.value = true;
    nextTick(() => {
      newStageNameInput.value?.focus();
      if (boardScrollContainer.value) {
        boardScrollContainer.value.scrollLeft =
          boardScrollContainer.value.scrollWidth;
      }
    });
  };

  const cancelStageDraft = () => {
    isCreatingStageDraft.value = false;
    newStageName.value = '';
    newStageColor.value = defaultStageColor;
  };

  const createStage = async () => {
    const name = newStageName.value.trim();
    if (!selectedBoard.value?.id || isCreatingStage.value) return;
    if (!name) {
      useAlert(t('KANBAN.ACTIONS.STAGE_NAME_REQUIRED'));
      nextTick(() => newStageNameInput.value?.focus());
      return;
    }

    isCreatingStage.value = true;

    try {
      const response = await KanbanBoardsAPI.createStage(
        selectedBoard.value.id,
        {
          stage: {
            name,
            color: newStageColor.value,
            position: stages.value.length,
          },
        }
      );
      cancelStageDraft();
      pendingScrollToStageId.value = normalizePayload(response.data).id;
      await refreshSelectedBoard();
      useAlert(t('KANBAN.ACTIONS.CREATE_STAGE_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
    } finally {
      isCreatingStage.value = false;
    }
  };

  const cancelEditingStage = () => {
    const stageId = editingStageId.value;
    editingStageId.value = null;
    if (!stageId) return;
    const { [stageId]: _name, ...restNames } = stageNames.value;
    const { [stageId]: _color, ...restColors } = stageColors.value;
    stageNames.value = restNames;
    stageColors.value = restColors;
  };

  const updateStage = async stage => {
    const name = String(stageNames.value[stage.id] || '').trim();
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || isActionActive(actionKey)) return;
    if (!name) {
      useAlert(t('KANBAN.ACTIONS.STAGE_NAME_REQUIRED'));
      nextTick(() => stageNameInputs.get(stage.id)?.focus());
      return;
    }

    startAction(actionKey);

    try {
      const stagePayload = { name };
      if (!isTerminalStage(stage)) {
        stagePayload.color = stageColors.value[stage.id] || defaultStageColor;
      }

      await KanbanBoardsAPI.updateStage(selectedBoard.value.id, stage.id, {
        stage: stagePayload,
      });
      cancelEditingStage();
      await refreshSelectedBoard();
      useAlert(t('KANBAN.ACTIONS.UPDATE_STAGE_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.UPDATE_STAGE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const stageCardCount = stage =>
    stage?.cardsCount ?? stage?.cards_count ?? stage?.cards?.length ?? 0;

  const openRemoveStageConfirmation = stage => {
    stagePendingRemoval.value = stage;
    showRemoveStageConfirmation.value = true;
  };

  const closeRemoveStageConfirmation = () => {
    showRemoveStageConfirmation.value = false;
    stagePendingRemoval.value = null;
  };

  const removeStage = async stage => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.deleteStage(selectedBoard.value.id, stage.id);
      await refreshSelectedBoard();
      useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const confirmRemoveStage = async () => {
    const stage = stagePendingRemoval.value;
    closeRemoveStageConfirmation();

    if (!stage) return;

    await removeStage(stage);
  };

  const copyStage = async (stage, { name }) => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      const response = await KanbanBoardsAPI.copyStage(
        selectedBoard.value.id,
        stage.id,
        {
          stage: { name },
        }
      );
      pendingScrollToStageId.value = normalizePayload(response.data).id;
      await refreshSelectedBoard();
      useAlert(t('KANBAN.STAGE_MENU.SUCCESS.COPY'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.CREATE_STAGE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const moveStage = async (stage, { kanbanBoardId, position }) => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.moveStage(selectedBoard.value.id, stage.id, {
        target_kanban_board_id: kanbanBoardId,
        position,
      });
      await Promise.all([
        refreshSelectedBoard(),
        store.dispatch('kanbanBoards/fetchBoards'),
      ]);
      useAlert(t('KANBAN.STAGE_MENU.SUCCESS.MOVE'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const sortStageCards = async (stage, { sortBy }) => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.sortStageCards(selectedBoard.value.id, stage.id, {
        sort_by: sortBy,
      });
      await refreshStageFirstPages([stage.id]);
      useAlert(t('KANBAN.STAGE_MENU.SUCCESS.SORT'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const moveAllStageCards = async (stage, { targetStageId }) => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.moveAllStageCards(
        selectedBoard.value.id,
        stage.id,
        {
          target_stage_id: targetStageId,
        }
      );
      await refreshStageFirstPages([stage.id, targetStageId]);
      useAlert(t('KANBAN.STAGE_MENU.SUCCESS.MOVE_CARDS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const openRemoveStageCardsConfirmation = stage => {
    stageCardsPendingRemoval.value = stage;
    showRemoveStageCardsConfirmation.value = true;
  };

  const closeRemoveStageCardsConfirmation = () => {
    showRemoveStageCardsConfirmation.value = false;
    stageCardsPendingRemoval.value = null;
  };

  const removeAllStageCards = async stage => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.deleteAllStageCards(
        selectedBoard.value.id,
        stage.id
      );
      await refreshStageFirstPages([stage.id]);
      useAlert(t('KANBAN.STAGE_MENU.SUCCESS.DELETE_CARDS'));
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
    } finally {
      endAction(actionKey);
    }
  };

  const confirmRemoveStageCards = async () => {
    const stage = stageCardsPendingRemoval.value;
    closeRemoveStageCardsConfirmation();

    if (!stage) return;

    await removeAllStageCards(stage);
  };

  const reorderStageByPosition = async (stage, position) => {
    const actionKey = `stage-${stage.id}`;
    if (!selectedBoard.value?.id || !stage?.id || isActionActive(actionKey)) {
      return;
    }

    startAction(actionKey);

    try {
      await KanbanBoardsAPI.reorderStage(selectedBoard.value.id, stage.id, {
        position,
      });
      await refreshSelectedBoard();
    } catch (error) {
      showActionError(error, t('KANBAN.ACTIONS.REORDER_STAGE_ERROR'));
      await refreshSelectedBoard();
    } finally {
      endAction(actionKey);
    }
  };

  const onStageDragEnd = async event => {
    stopBoardAutoScroll();
    const stageId = Number(event?.item?.dataset?.stageId);
    const newIndex = event?.newIndex;
    const oldIndex = event?.oldIndex;
    if (!stageId || oldIndex === newIndex || newIndex === undefined) return;

    const stage = stages.value.find(item => item.id === stageId);
    if (!stage) return;

    await reorderStageByPosition(stage, newIndex + 1);
  };

  return {
    cancelEditingStage,
    cancelStageDraft,
    closeRemoveStageCardsConfirmation,
    closeRemoveStageConfirmation,
    confirmRemoveStage,
    confirmRemoveStageCards,
    copyStage,
    createStage,
    moveAllStageCards,
    moveStage,
    onStageDragEnd,
    openRemoveStageCardsConfirmation,
    openRemoveStageConfirmation,
    openStageDraft,
    removeAllStageCards,
    removeStage,
    reorderStageByPosition,
    setStageNameInput,
    sortStageCards,
    stageCardCount,
    startEditingStage,
    updateStage,
    updateStageColorDraft,
    updateStageNameDraft,
  };
}
