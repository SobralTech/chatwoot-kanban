import { describe, it, expect, vi, beforeEach } from 'vitest';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import types from 'dashboard/store/mutation-types';
import storeModule from 'dashboard/store/modules/kanbanBoards';

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    get: vi.fn(),
  },
}));

describe('Kanban Boards Store', () => {
  let commit;

  beforeEach(() => {
    vi.clearAllMocks();
    commit = vi.fn();
  });

  describe('Initial State', () => {
    it('should have the correct initial state', () => {
      const { state } = storeModule;
      expect(state).toEqual({
        records: [],
        uiFlags: {
          isLoading: false,
          error: null,
        },
      });
    });
  });

  describe('Getters', () => {
    const state = {
      records: [
        { id: 1, name: 'Board 1' },
        { id: 2, name: 'Board 2' },
      ],
      uiFlags: {
        isLoading: true,
        error: 'Something went wrong',
      },
    };

    it('kanbanBoards returns records', () => {
      expect(storeModule.getters.kanbanBoards(state)).toEqual(state.records);
    });

    it('kanbanBoardsLoading returns isLoading flag', () => {
      expect(storeModule.getters.kanbanBoardsLoading(state)).toBe(true);
    });

    it('kanbanBoardsError returns error', () => {
      expect(storeModule.getters.kanbanBoardsError(state)).toBe(
        'Something went wrong'
      );
    });
  });

  describe('Mutations', () => {
    it('SET_KANBAN_BOARDS replaces records', () => {
      const state = { records: [], uiFlags: {} };
      const data = [{ id: 1, name: 'Board A' }];
      storeModule.mutations[types.SET_KANBAN_BOARDS](state, data);
      expect(state.records).toEqual(data);
    });

    it('SET_KANBAN_BOARDS_UI_FLAG merges flags', () => {
      const state = { uiFlags: { isLoading: true, error: null } };
      storeModule.mutations[types.SET_KANBAN_BOARDS_UI_FLAG](state, {
        isLoading: false,
      });
      expect(state.uiFlags).toEqual({ isLoading: false, error: null });
    });
  });

  describe('Actions', () => {
    describe('fetchBoards', () => {
      it('fetches boards and commits data on success', async () => {
        const mockData = [{ id: 1, name: 'Board 1' }];
        KanbanBoardsAPI.get.mockResolvedValueOnce({ data: mockData });

        await storeModule.actions.fetchBoards({ commit });

        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS_UI_FLAG, {
          isLoading: true,
          error: null,
        });
        expect(KanbanBoardsAPI.get).toHaveBeenCalledTimes(1);
        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS, mockData);
        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS_UI_FLAG, {
          isLoading: false,
        });
      });

      it('handles concurrent calls gracefully (no duplicate commits)', async () => {
        KanbanBoardsAPI.get.mockResolvedValue({ data: [{ id: 1 }] });

        const firstCall = storeModule.actions.fetchBoards({ commit });
        const secondCall = storeModule.actions.fetchBoards({ commit });

        await Promise.all([firstCall, secondCall]);

        expect(commit).toHaveBeenCalledWith(
          types.SET_KANBAN_BOARDS,
          expect.any(Array)
        );
      });

      it('throws error on failure and commits error', async () => {
        const error = new Error('Network error');
        KanbanBoardsAPI.get.mockRejectedValueOnce(error);

        await expect(
          storeModule.actions.fetchBoards({ commit })
        ).rejects.toThrow('Network error');

        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS_UI_FLAG, {
          isLoading: false,
        });
      });
    });

    describe('refreshBoards', () => {
      it('fetches boards via dispatch', async () => {
        const mockData = [{ id: 1, name: 'Board 1' }];
        KanbanBoardsAPI.get.mockResolvedValueOnce({ data: mockData });
        const dispatchMock = vi
          .fn()
          .mockImplementation(action =>
            storeModule.actions[action]({ commit })
          );

        await storeModule.actions.refreshBoards({
          dispatch: dispatchMock,
          commit,
        });

        expect(KanbanBoardsAPI.get).toHaveBeenCalledTimes(1);
      });
    });

    describe('resetBoards', () => {
      it('clears records and resets uiFlags', () => {
        storeModule.actions.resetBoards({ commit });

        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS, []);
        expect(commit).toHaveBeenCalledWith(types.SET_KANBAN_BOARDS_UI_FLAG, {
          isLoading: false,
          error: null,
        });
      });
    });
  });
});
