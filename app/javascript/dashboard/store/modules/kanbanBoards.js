import camelcaseKeys from 'camelcase-keys';
import KanbanBoardsAPI from '../../api/kanbanBoards';
import types from '../mutation-types';

const state = {
  records: [],
  uiFlags: {
    isLoading: false,
    error: null,
  },
};

const requestStateByStore = new WeakMap();
const unscopedRequestState = { requestId: 0, inFlightFetch: null };

const requestStateFor = rootState => {
  if (!rootState) return unscopedRequestState;

  if (!requestStateByStore.has(rootState)) {
    requestStateByStore.set(rootState, { requestId: 0, inFlightFetch: null });
  }

  return requestStateByStore.get(rootState);
};

export const getters = {
  kanbanBoards: _state => _state.records,
  kanbanBoardsLoading: _state => _state.uiFlags.isLoading,
  kanbanBoardsError: _state => _state.uiFlags.error,
};

export const actions = {
  fetchBoards: ({ commit, rootState }, { force = false } = {}) => {
    const requestState = requestStateFor(rootState);
    if (requestState.inFlightFetch && !force) {
      return requestState.inFlightFetch;
    }

    requestState.requestId += 1;
    const { requestId } = requestState;

    commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: true, error: null });

    const request = (async () => {
      try {
        const response = await KanbanBoardsAPI.get();
        if (requestId !== requestState.requestId) return;
        commit(types.SET_KANBAN_BOARDS, response.data);
      } catch (error) {
        if (requestId !== requestState.requestId) return;
        const message = error?.response?.data?.error || error.message;
        commit(types.SET_KANBAN_BOARDS_UI_FLAG, { error: message });
        throw error;
      } finally {
        if (requestId === requestState.requestId) {
          commit(types.SET_KANBAN_BOARDS_UI_FLAG, { isLoading: false });
        }
      }
    })();

    requestState.inFlightFetch = request.finally(() => {
      if (requestId === requestState.requestId) {
        requestState.inFlightFetch = null;
      }
    });

    return requestState.inFlightFetch;
  },

  refreshBoards: async ({ dispatch }) => {
    return dispatch('fetchBoards', { force: true });
  },

  resetBoards: ({ commit, rootState }) => {
    const requestState = requestStateFor(rootState);
    requestState.requestId += 1;
    requestState.inFlightFetch = null;
    commit(types.SET_KANBAN_BOARDS, []);
    commit(types.SET_KANBAN_BOARDS_UI_FLAG, {
      isLoading: false,
      error: null,
    });
  },
};

export const mutations = {
  [types.SET_KANBAN_BOARDS](_state, data) {
    _state.records = camelcaseKeys(data || [], { deep: true });
  },
  [types.UPDATE_KANBAN_BOARD_CARD_COUNTS](_state, { boardId, stagesSummary }) {
    const cardCountsByStageId = new Map(
      stagesSummary.map(stage => [Number(stage.id), stage.cardsCount])
    );

    _state.records = _state.records.map(board => {
      if (Number(board.id) !== Number(boardId)) return board;

      return {
        ...board,
        cardsCount: stagesSummary.reduce(
          (total, stage) => total + stage.cardsCount,
          0
        ),
        stagesSummary: board.stagesSummary.map(stage => ({
          ...stage,
          cardsCount:
            cardCountsByStageId.get(Number(stage.id)) ?? stage.cardsCount,
        })),
      };
    });
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
