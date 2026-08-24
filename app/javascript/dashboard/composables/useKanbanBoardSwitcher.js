import { ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

/**
 * The board picker in the header: which board the route is on, moving to
 * another one, and renaming one in place from the list.
 */
export function useKanbanBoardSwitcher({
  activeBoardId,
  agents,
  boards,
  hasBoards,
  hasError,
  inboxes,
  route,
  router,
  selectedBoard,
  showBoardWithSnapshot,
  store,
  t,
}) {
  const isBoardDropdownOpen = ref(false);
  const renamingBoardId = ref(null);
  const renameValue = ref('');
  const isRenamingBoard = ref(false);

  const accountId = () => route.params.accountId;

  const cancelBoardRename = () => {
    renamingBoardId.value = null;
    renameValue.value = '';
  };

  const startBoardRename = board => {
    renamingBoardId.value = board.id;
    renameValue.value = board.name || '';
  };

  const confirmBoardRename = async () => {
    const board = boards.value.find(item => item.id === renamingBoardId.value);
    const name = renameValue.value.trim();
    if (!board || !name || isRenamingBoard.value) return;

    if (name === board.name) {
      cancelBoardRename();
      return;
    }

    isRenamingBoard.value = true;
    try {
      await KanbanBoardsAPI.update(board.id, { kanban_board: { name } });
      await store.dispatch('kanbanBoards/refreshBoards');
      // The header title reads from selectedBoard, which is loaded by showBoard
      // rather than from the board list, so patch it instead of refetching.
      if (selectedBoard.value?.id === board.id) selectedBoard.value.name = name;
      cancelBoardRename();
    } catch (error) {
      // Keep the row in edit mode so the name can be corrected in place, most
      // commonly after the per-account uniqueness check rejects a duplicate.
      useAlert(apiErrorMessage(error, t('KANBAN.ACTIONS.RENAME_BOARD_ERROR')));
    } finally {
      isRenamingBoard.value = false;
    }
  };

  const closeBoardDropdown = () => {
    isBoardDropdownOpen.value = false;
    cancelBoardRename();
  };

  const toggleBoardDropdown = () => {
    isBoardDropdownOpen.value = hasBoards.value && !isBoardDropdownOpen.value;
  };

  const goToOverview = () =>
    router.push({
      name: 'kanban_boards',
      params: { accountId: accountId() },
    });

  const selectBoard = boardId => {
    if (boardId === activeBoardId.value) return;

    closeBoardDropdown();
    router.push({
      name: 'kanban_board_show',
      params: { accountId: accountId(), boardId },
    });
  };

  const goToCreateBoard = () => {
    closeBoardDropdown();
    router.push({
      name: 'kanban_board_create_form',
      params: { accountId: accountId() },
    });
  };

  // The board page is reachable without a board in the route, so the first load
  // also decides which board that should be.
  const fetchBoards = async () => {
    hasError.value = false;

    try {
      await Promise.all([
        store.dispatch('kanbanBoards/fetchBoards'),
        inboxes.value.length
          ? Promise.resolve()
          : store.dispatch('inboxes/get'),
        agents.value.length ? Promise.resolve() : store.dispatch('agents/get'),
        store.dispatch('labels/get'),
      ]);

      const nextBoardId = activeBoardId.value || boards.value[0]?.id;
      if (nextBoardId && !activeBoardId.value) {
        router.replace({
          name: 'kanban_board_show',
          params: { accountId: accountId(), boardId: nextBoardId },
        });
        return;
      }

      if (nextBoardId) await showBoardWithSnapshot(nextBoardId);
    } catch {
      hasError.value = true;
      selectedBoard.value = null;
    }
  };

  return {
    isBoardDropdownOpen,
    isRenamingBoard,
    renameValue,
    renamingBoardId,
    cancelBoardRename,
    closeBoardDropdown,
    confirmBoardRename,
    fetchBoards,
    goToCreateBoard,
    goToOverview,
    selectBoard,
    startBoardRename,
    toggleBoardDropdown,
  };
}
