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

  moveStage(boardId, stageId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/stages/${stageId}/move`,
      payload
    );
  }

  sortStageCards(boardId, stageId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/stages/${stageId}/sort_cards`,
      payload
    );
  }

  moveAllStageCards(boardId, stageId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/stages/${stageId}/move_cards`,
      payload
    );
  }

  deleteAllStageCards(boardId, stageId) {
    return axios.delete(`${this.url}/${boardId}/stages/${stageId}/cards`);
  }

  getBoards(config = {}) {
    return axios.get(this.url, config);
  }

  templates() {
    return axios.get(`${this.url}/templates`);
  }

  showBoard(boardId, config = {}) {
    return axios.get(`${this.url}/${boardId}`, config);
  }

  getSummary(boardId, config = {}) {
    return axios.get(`${this.url}/${boardId}/summary`, config);
  }

  getSettings(boardId) {
    return axios.get(`${this.url}/${boardId}/settings`);
  }

  updateSettings(boardId, payload) {
    return axios.patch(`${this.url}/${boardId}/settings`, payload);
  }

  importExistingConversations(boardId, payload) {
    return axios.post(
      `${this.url}/${boardId}/settings/import_existing_conversations`,
      payload
    );
  }

  getAutomationRules(boardId) {
    return axios.get(`${this.url}/${boardId}/automation_rules`);
  }

  createAutomationRule(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/automation_rules`, payload);
  }

  updateAutomationRule(boardId, ruleId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/automation_rules/${ruleId}`,
      payload
    );
  }

  toggleAutomationRule(boardId, ruleId) {
    return axios.patch(
      `${this.url}/${boardId}/automation_rules/${ruleId}/toggle`
    );
  }

  deleteAutomationRule(boardId, ruleId) {
    return axios.delete(`${this.url}/${boardId}/automation_rules/${ruleId}`);
  }

  previewAutomationRule(boardId, payload) {
    return axios.post(
      `${this.url}/${boardId}/automation_rules/preview`,
      payload
    );
  }

  getAutomationLogs(boardId, params = {}) {
    return axios.get(`${this.url}/${boardId}/automation_logs`, { params });
  }

  getConversationCards(conversationId, config = {}) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/kanban_cards`,
      config
    );
  }

  createConversationCard(conversationId, payload, config = {}) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/kanban_cards`,
      payload,
      config
    );
  }

  getStageCards(boardId, stageId, params = {}) {
    return axios.get(`${this.url}/${boardId}/stages/${stageId}/cards`, {
      params,
    });
  }

  createManualCard(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/cards/manual`, payload);
  }

  bulkAction(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/cards/bulk_actions`, payload);
  }

  lookupCards(boardId, { contactId, signal }) {
    return axios.get(`${this.url}/${boardId}/cards/lookup`, {
      params: { contact_id: contactId },
      signal,
    });
  }

  updateCardById(boardId, cardId, payload) {
    return axios.patch(`${this.url}/${boardId}/cards/by_id/${cardId}`, payload);
  }

  reopenCardById(boardId, cardId) {
    return axios.patch(`${this.url}/${boardId}/cards/by_id/${cardId}/reopen`);
  }

  showCardById(boardId, cardId) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}`);
  }

  getCardEvents(boardId, cardId, params = {}) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}/events`, {
      params,
    });
  }

  getCardNotes(boardId, cardId, params = {}) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}/notes`, {
      params,
    });
  }

  createCardNote(boardId, cardId, payload) {
    return axios.post(
      `${this.url}/${boardId}/cards/by_id/${cardId}/notes`,
      payload
    );
  }

  updateCardNote(boardId, cardId, noteId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/cards/by_id/${cardId}/notes/${noteId}`,
      { note: payload }
    );
  }

  deleteCardNote(boardId, cardId, noteId) {
    return axios.delete(
      `${this.url}/${boardId}/cards/by_id/${cardId}/notes/${noteId}`
    );
  }

  updateCardDetailsById(boardId, cardId, payload) {
    return axios.patch(`${this.url}/${boardId}/cards/by_id/${cardId}`, {
      card: payload,
    });
  }

  getCardLabels(boardId, cardId) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}/labels`);
  }

  updateCardLabels(boardId, cardId, labels) {
    return axios.put(`${this.url}/${boardId}/cards/by_id/${cardId}/labels`, {
      labels,
    });
  }

  getCardAssignees(boardId, cardId) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}/assignees`);
  }

  updateCardAssignees(boardId, cardId, assigneeIds) {
    return axios.put(`${this.url}/${boardId}/cards/by_id/${cardId}/assignees`, {
      assignee_ids: assigneeIds,
    });
  }

  reorderCardById(boardId, cardId, payloadOrDirection) {
    const payload =
      typeof payloadOrDirection === 'string'
        ? { direction: payloadOrDirection }
        : payloadOrDirection;
    return axios.patch(
      `${this.url}/${boardId}/cards/by_id/${cardId}/reorder`,
      payload
    );
  }

  moveCardToBoard(boardId, cardId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/cards/by_id/${cardId}/move`,
      payload
    );
  }

  deleteCardById(boardId, cardId) {
    return axios.delete(`${this.url}/${boardId}/cards/by_id/${cardId}`);
  }

  getReasons(boardId) {
    return axios.get(`${this.url}/${boardId}/reasons`);
  }

  createReason(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/reasons`, payload);
  }

  updateReason(boardId, reasonId, payload) {
    return axios.patch(`${this.url}/${boardId}/reasons/${reasonId}`, payload);
  }

  deleteReason(boardId, reasonId) {
    return axios.delete(`${this.url}/${boardId}/reasons/${reasonId}`);
  }

  getCustomFields(boardId) {
    return axios.get(`${this.url}/${boardId}/custom_fields`);
  }

  createCustomField(boardId, payload) {
    return axios.post(`${this.url}/${boardId}/custom_fields`, payload);
  }

  updateCustomField(boardId, fieldId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/custom_fields/${fieldId}`,
      payload
    );
  }

  deleteCustomField(boardId, fieldId) {
    return axios.delete(`${this.url}/${boardId}/custom_fields/${fieldId}`);
  }

  getCardFieldValues(boardId, cardId) {
    return axios.get(
      `${this.url}/${boardId}/cards/by_id/${cardId}/field_values`
    );
  }

  updateCardFieldValues(boardId, cardId, payload) {
    return axios.put(
      `${this.url}/${boardId}/cards/by_id/${cardId}/field_values`,
      payload
    );
  }

  getCardProducts(boardId, cardId) {
    return axios.get(`${this.url}/${boardId}/cards/by_id/${cardId}/products`);
  }

  createCardProduct(boardId, cardId, payload) {
    return axios.post(
      `${this.url}/${boardId}/cards/by_id/${cardId}/products`,
      payload
    );
  }

  updateCardProduct(boardId, cardId, productId, payload) {
    return axios.patch(
      `${this.url}/${boardId}/cards/by_id/${cardId}/products/${productId}`,
      payload
    );
  }

  deleteCardProduct(boardId, cardId, productId) {
    return axios.delete(
      `${this.url}/${boardId}/cards/by_id/${cardId}/products/${productId}`
    );
  }
}

export default new KanbanBoardsAPI();
