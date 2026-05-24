/* global axios */
import ApiClient from './ApiClient';

class KanbanBoardsAPI extends ApiClient {
  constructor() {
    super('kanban_boards', { accountScoped: true });
  }

  createStage(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/stages`, payload);
  }

  updateStage(boardId, stageId, payload) {
    return axios.patch(`${this.url}/${boardId}/stages/${stageId}`, payload);
  }

  reorderStage(boardId, stageId, payloadOrDirection) {
    const payload =
      typeof payloadOrDirection === 'string'
        ? { direction: payloadOrDirection }
        : payloadOrDirection;
    return axios.patch(
      `${this.url}/${boardId}/stages/${stageId}/reorder`,
      payload
    );
  }

  deleteStage(boardId, stageId) {
    return axios.delete(`${this.url}/${boardId}/stages/${stageId}`);
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

  reorderCard(boardId, conversationId, payloadOrDirection) {
    const payload =
      typeof payloadOrDirection === 'string'
        ? { direction: payloadOrDirection }
        : payloadOrDirection;
    return axios.patch(
      `${this.url}/${boardId}/cards/${conversationId}/reorder`,
      payload
    );
  }

  deleteCard(boardId, conversationId) {
    return axios.delete(`${this.url}/${boardId}/cards/${conversationId}`);
  }
}

export default new KanbanBoardsAPI();
