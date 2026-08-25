/* global axios */
import ApiClient from './ApiClient';

const getTimeOffset = () => -new Date().getTimezoneOffset() / 60;

class KanbanReportsAPI extends ApiClient {
  constructor() {
    super('kanban_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  // eslint-disable-next-line class-methods-use-this
  buildParams({
    boardId: kanban_board_id,
    from: since,
    to: until,
    groupBy: group_by,
    businessHours: business_hours = false,
    agentIds: agent_ids = [],
    inboxIds: inbox_ids = [],
    labels = [],
    timezoneOffset: timezone_offset = getTimeOffset(),
  } = {}) {
    return {
      kanban_board_id,
      since,
      until,
      group_by,
      business_hours,
      agent_ids,
      inbox_ids,
      labels,
      timezone_offset,
    };
  }

  getReports(params = {}) {
    return axios.get(this.url, {
      params: this.buildParams(params),
    });
  }

  getDashboard(params = {}) {
    return this.getReports(params);
  }

  getCsv(report, params = {}) {
    return axios.get(`${this.url}/${report}`, {
      params: this.buildParams(params),
    });
  }
}

export default new KanbanReportsAPI();
