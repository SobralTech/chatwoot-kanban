import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';

import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

export function useKanbanBoardCreation({ boards, t }) {
  const route = useRoute();
  const router = useRouter();
  const store = useStore();

  const showCreateBoardDialog = ref(false);
  const createBoardError = ref('');
  const isCreatingBoard = ref(false);

  const openCreateBoardDialog = () => {
    showCreateBoardDialog.value = true;
    createBoardError.value = '';
  };

  const closeCreateBoardDialog = () => {
    showCreateBoardDialog.value = false;
    createBoardError.value = '';
  };

  const createBoard = async name => {
    const trimmedName = name.trim();
    if (!trimmedName || isCreatingBoard.value) return;

    isCreatingBoard.value = true;
    createBoardError.value = '';

    try {
      const response = await KanbanBoardsAPI.create({
        kanban_board: {
          name: trimmedName,
          position: boards.value.length,
        },
      });
      const board = camelcaseKeys(response.data || {}, { deep: true });
      showCreateBoardDialog.value = false;
      await store.dispatch('kanbanBoards/refreshBoards');
      router.push({
        name: 'kanban_board_show',
        params: {
          accountId: route.params.accountId,
          boardId: board.id,
        },
      });
      useAlert(t('KANBAN.ACTIONS.CREATE_BOARD_SUCCESS'));
    } catch (error) {
      createBoardError.value =
        error?.response?.data?.error || t('KANBAN.ACTIONS.CREATE_BOARD_ERROR');
    } finally {
      isCreatingBoard.value = false;
    }
  };

  return {
    showCreateBoardDialog,
    createBoardError,
    isCreatingBoard,
    openCreateBoardDialog,
    closeCreateBoardDialog,
    createBoard,
  };
}
