import { ref } from 'vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const BULK_ACTION_KEY = 'bulk-kanban-action';

export function useKanbanBulkActions({
  clearCardSelection,
  endAction,
  findCardStageId,
  getErrorMessage,
  isBoardBusy,
  refreshStageFirstPages,
  selectedBoard,
  selectedCardIds,
  selectionLimit,
  startAction,
  store,
  t,
  useAlert,
}) {
  const showBulkDeleteConfirmation = ref(false);

  // Only the codes a user can actually provoke get their own copy; everything else the
  // API rejects is a payload the UI cannot produce.
  const errorMessage = error => {
    switch (error?.response?.data?.error) {
      case 'lost_reason_required':
        return t('KANBAN.CARD.STATUS.REASON_REQUIRED');
      case 'bulk_action_limit_exceeded':
        return t('KANBAN.BULK.LIMIT', { count: selectionLimit.value });
      default:
        return getErrorMessage(error, t('KANBAN.BULK.ERROR'));
    }
  };

  // A cross-board move refreshes the source stages here; the target board is refreshed
  // through its summary because it is not mounted in this view.
  const affectedStageIds = (action, payload) => {
    const sourceStageIds = [...selectedCardIds.value].map(cardId =>
      findCardStageId({ id: cardId })
    );
    const terminalStageId =
      action === 'lose' ? selectedBoard.value?.lostStageId : null;
    const isCrossBoardMove =
      action === 'move' &&
      payload.target_kanban_board_id &&
      Number(payload.target_kanban_board_id) !==
        Number(selectedBoard.value?.id);
    const targetStageId = isCrossBoardMove ? null : payload.kanban_stage_id;

    return [...sourceStageIds, targetStageId, terminalStageId].filter(Boolean);
  };

  const applyBulkAction = async ({ action, payload = {} } = {}) => {
    if (!selectedBoard.value?.id || !selectedCardIds.value.size) return;
    if (isBoardBusy.value) return;

    const cardIds = [...selectedCardIds.value];
    const stageIds = affectedStageIds(action, payload);
    startAction(BULK_ACTION_KEY);

    try {
      const response = await KanbanBoardsAPI.bulkAction(
        selectedBoard.value.id,
        {
          operation: action,
          card_ids: cardIds,
          payload,
        }
      );
      const succeeded = response.data?.succeeded || [];
      const failed = response.data?.failed || [];

      await refreshStageFirstPages(stageIds);
      if (
        action === 'move' &&
        payload.target_kanban_board_id &&
        Number(payload.target_kanban_board_id) !==
          Number(selectedBoard.value.id)
      ) {
        await store?.dispatch('kanbanBoards/fetchBoards');
      }
      clearCardSelection();

      if (failed.length) {
        useAlert(
          t('KANBAN.BULK.PARTIAL', {
            succeeded: succeeded.length,
            total: cardIds.length,
            failed: failed.length,
          })
        );
      } else {
        useAlert(t('KANBAN.BULK.SUCCESS', { count: succeeded.length }));
      }
    } catch (error) {
      useAlert(errorMessage(error));
    } finally {
      endAction(BULK_ACTION_KEY);
    }
  };

  const openBulkDeleteConfirmation = () => {
    if (!selectedCardIds.value.size || isBoardBusy.value) return;

    showBulkDeleteConfirmation.value = true;
  };

  const closeBulkDeleteConfirmation = () => {
    showBulkDeleteConfirmation.value = false;
  };

  const confirmBulkDelete = async () => {
    closeBulkDeleteConfirmation();
    await applyBulkAction({ action: 'delete' });
  };

  return {
    applyBulkAction,
    closeBulkDeleteConfirmation,
    confirmBulkDelete,
    openBulkDeleteConfirmation,
    showBulkDeleteConfirmation,
  };
}
