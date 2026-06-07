import KanbanBoardsAPI from '../../api/kanbanBoards';
import types from '../mutation-types';

const state = {
  records: [],
  uiFlags: {
    isLoading: false,
    error: null,
  },
};

let fetchPromise = null;

export const getters = {
  kanbanBoards: _state => _state.records,
  kanbanBoardsLoading: _state => _state.uiFlags.isLoading,
  kanbanBoardsError: _state => _state.uiFlags.error,
};

export const actions = {
  fetchBoards: async ({ commit }) => {
    if (fetchPromise) return fetchPromise;

    commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: true, error: null });

    const promise = (async () => {
      try {
        const response = await KanbanBoardsAPI.get();
        commit(types.SET_KANBAN_BOARDS, response.data);
        return response.data;
      } catch (error) {
        const message = error?.response?.data?.error || error.message;
        commit(types.SET_KANBAN_BOARDS_UI_FLAG, { error: message });
        throw error;
      } finally {
        commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: false });
      }
    })();

    fetchPromise = promise.then(
      () => {
        fetchPromise = null;
      },
      () => {
        fetchPromise = null;
      }
    );

    return promise;
  },

  refreshBoards: async ({ dispatch }) => {
    fetchPromise = null;
    return dispatch('fetchBoards');
  },

  resetBoards: ({ commit }) => {
    fetchPromise = null;
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
