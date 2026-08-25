import ApiClient from '../ApiClient';
import kanbanReports from '../kanbanReports';

describe('#KanbanReportsAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    Object.defineProperty(kanbanReports, 'accountIdFromRoute', {
      get: () => '1',
      configurable: true,
    });
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('creates a v2 account-scoped client', () => {
    expect(kanbanReports).toBeInstanceOf(ApiClient);
    expect(kanbanReports.apiVersion).toBe('/api/v2');
  });

  it('loads the aggregate report with the supported filters', () => {
    kanbanReports.getDashboard({
      boardId: 8,
      from: 100,
      to: 200,
      groupBy: 'week',
      agentIds: [2],
      inboxIds: [3],
      labels: ['vip'],
      timezoneOffset: -3,
    });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v2/accounts/1/kanban_reports',
      {
        params: {
          kanban_board_id: 8,
          since: 100,
          until: 200,
          group_by: 'week',
          business_hours: false,
          agent_ids: [2],
          inbox_ids: [3],
          labels: ['vip'],
          timezone_offset: -3,
        },
      }
    );
  });

  it('downloads each table report with the same filter contract', () => {
    kanbanReports.getCsv('products', { boardId: 8, agentIds: [2] });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v2/accounts/1/kanban_reports/products',
      expect.objectContaining({
        params: expect.objectContaining({
          kanban_board_id: 8,
          agent_ids: [2],
        }),
      })
    );
  });
});
