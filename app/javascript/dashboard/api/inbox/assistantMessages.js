/* global axios */
import ApiClient from '../ApiClient';

class AssistantMessagesAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get(conversationId, page = 1) {
    return axios.get(`${this.url}/${conversationId}/assistant_messages`, {
      params: { page },
    });
  }

  create({ conversationId, question }) {
    return axios.post(`${this.url}/${conversationId}/assistant_messages`, {
      question,
    });
  }

  sendToCustomer({ conversationId, assistantMessageId }) {
    return axios.post(
      `${this.url}/${conversationId}/assistant_messages/${assistantMessageId}/send_to_customer`
    );
  }
}

export default new AssistantMessagesAPI();
