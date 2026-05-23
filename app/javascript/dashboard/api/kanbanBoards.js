/* global axios */
import ApiClient from './ApiClient';

class KanbanBoardsAPI extends ApiClient {
  constructor() {
    super('kanban_boards', { accountScoped: true });
  }

  createStage(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/stages`, payload);
  }

  createCard(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/cards`, payload);
  }

  updateCard(boardId, conversationId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/cards/${conversationId}`,
      payload
    );
  }

  deleteCard(boardId, conversationId) {
    return axios.delete(`${this.url}/${boardId}/cards/${conversationId}`);
  }
}

export default new KanbanBoardsAPI();
