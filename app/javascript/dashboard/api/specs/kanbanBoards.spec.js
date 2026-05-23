import kanbanBoards from '../kanbanBoards';
import ApiClient from '../ApiClient';

describe('#KanbanBoardsAPI', () => {
  it('creates correct instance', () => {
    expect(kanbanBoards).toBeInstanceOf(ApiClient);
    expect(kanbanBoards).toHaveProperty('get');
    expect(kanbanBoards).toHaveProperty('show');
    expect(kanbanBoards).toHaveProperty('create');
    expect(kanbanBoards).toHaveProperty('update');
    expect(kanbanBoards).toHaveProperty('delete');
    expect(kanbanBoards).toHaveProperty('createStage');
    expect(kanbanBoards).toHaveProperty('updateStage');
    expect(kanbanBoards).toHaveProperty('deleteStage');
    expect(kanbanBoards).toHaveProperty('createCard');
    expect(kanbanBoards).toHaveProperty('updateCard');
    expect(kanbanBoards).toHaveProperty('deleteCard');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      Object.defineProperty(kanbanBoards, 'accountIdFromRoute', {
        get: () => '1',
        configurable: true,
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
      vi.clearAllMocks();
    });

    it('#createStage', () => {
      const payload = { stage: { name: 'New' } };
      kanbanBoards.createStage(2, payload);

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/stages',
        payload
      );
    });

    it('#updateStage', () => {
      const payload = { stage: { name: 'Won' } };
      kanbanBoards.updateStage(2, 3, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/stages/3',
        payload
      );
    });

    it('#deleteStage', () => {
      kanbanBoards.deleteStage(2, 3);

      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/stages/3'
      );
    });

    it('#createCard', () => {
      const payload = { card: { conversation_id: 10, kanban_stage_id: 3 } };
      kanbanBoards.createCard(2, payload);

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards',
        payload
      );
    });

    it('#updateCard', () => {
      const payload = { card: { kanban_stage_id: 4 } };
      kanbanBoards.updateCard(2, 10, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/10',
        payload
      );
    });

    it('#deleteCard', () => {
      kanbanBoards.deleteCard(2, 10);

      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/10'
      );
    });
  });
});
