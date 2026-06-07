import KanbanBoardsAPI from '../../api/kanbanBoards';
import types from '../mutation-types';

const state = {
  records: [],
  uiFlags: {
    isLoading: false,
    error: null,
  },
};

let fetchRequestId = 0;

export const getters = {
  kanbanBoards: _state => _state.records,
  kanbanBoardsLoading: _state => _state.uiFlags.isLoading,
  kanbanBoardsError: _state => _state.uiFlags.error,
};

export const actions = {
  fetchBoards: async ({ commit }) => {
    fetchRequestId += 1;
    const requestId = fetchRequestId;

    commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: true, error: null });

    try {
      const response = await KanbanBoardsAPI.get();
      if (requestId !== fetchRequestId) return;
      commit(types.SET_KANBAN_BOARDS, response.data);
    } catch (error) {
      if (requestId !== fetchRequestId) return;
      const message = error?.response?.data?.error || error.message;
      commit(types.SET_KANBAN_BOARDS_UI_FLAG, { error: message });
      throw error;
    } finally {
      if (requestId === fetchRequestId) {
        commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: false });
      }
    }
  },

  refreshBoards: async ({ dispatch }) => {
    return dispatch('fetchBoards');
  },

  resetBoards: ({ commit }) => {
    fetchRequestId += 1;
    commit(types.SET_KANBAN_BOARDS, []);
    commit(types.SET_KANBAN_BOARDS_UI_FLAG, {
      isLoading: false,
      error: null,
    });
  },
};

export const mutations = {
  [types.SET_KANBAN_BOARDS](_state, data) {
    _state.records = data;
  },
  [types.SET_KANBAN_BOARDS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
