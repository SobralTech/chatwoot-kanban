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
    expect(kanbanBoards).toHaveProperty('reorderStage');
    expect(kanbanBoards).toHaveProperty('deleteStage');
    expect(kanbanBoards).toHaveProperty('createManualCard');
    expect(kanbanBoards).toHaveProperty('updateCardById');
    expect(kanbanBoards).toHaveProperty('showCardById');
    expect(kanbanBoards).toHaveProperty('updateCardDetailsById');
    expect(kanbanBoards).toHaveProperty('getCardLabels');
    expect(kanbanBoards).toHaveProperty('updateCardLabels');
    expect(kanbanBoards).toHaveProperty('reorderCardById');
    expect(kanbanBoards).toHaveProperty('deleteCardById');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      put: vi.fn(() => Promise.resolve()),
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

    it('#reorderStage', () => {
      kanbanBoards.reorderStage(2, 3, 'left');

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/stages/3/reorder',
        { direction: 'left' }
      );
    });

    it('#reorderStage with payload object', () => {
      const payload = { position: 2 };
      kanbanBoards.reorderStage(2, 3, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/stages/3/reorder',
        payload
      );
    });

    it('#createManualCard', () => {
      const payload = {
        card: {
          kanban_stage_id: 3,
          contact_id: 123,
          inbox_id: 5,
          subject: 'Cotação de notebooks',
        },
      };
      kanbanBoards.createManualCard(2, payload);

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/manual',
        payload
      );
    });

    it('#updateCardById', () => {
      const payload = { card: { kanban_stage_id: 4 } };
      kanbanBoards.updateCardById(2, 501, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501',
        payload
      );
    });

    it('#showCardById', () => {
      kanbanBoards.showCardById(2, 501);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501'
      );
    });

    it('#updateCardDetailsById', () => {
      const payload = {
        subject: 'Cotação de notebooks',
        starts_at: '2026-06-01T09:00:00-03:00',
        due_at: '2026-06-05T18:00:00-03:00',
      };
      kanbanBoards.updateCardDetailsById(2, 501, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501',
        { card: payload }
      );
    });

    it('#updateCardDetailsById with null dates', () => {
      const payload = {
        subject: 'Cotação de notebooks',
        starts_at: null,
        due_at: null,
      };
      kanbanBoards.updateCardDetailsById(2, 501, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501',
        { card: payload }
      );
    });

    it('#getCardLabels', () => {
      kanbanBoards.getCardLabels(2, 501);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501/labels'
      );
    });

    it('#updateCardLabels', () => {
      const labels = ['hot', 'enterprise'];
      kanbanBoards.updateCardLabels(2, 501, labels);

      expect(axiosMock.put).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501/labels',
        { labels }
      );
    });

    it('#deleteCardById', () => {
      kanbanBoards.deleteCardById(2, 501);

      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501'
      );
    });

    it('#reorderCardById', () => {
      kanbanBoards.reorderCardById(2, 501, 'up');

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501/reorder',
        { direction: 'up' }
      );
    });

    it('#reorderCardById with payload object', () => {
      const payload = { card: { kanban_stage_id: 4, position: 1 } };
      kanbanBoards.reorderCardById(2, 501, payload);

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/kanban_boards/2/cards/by_id/501/reorder',
        payload
      );
    });
  });
});
