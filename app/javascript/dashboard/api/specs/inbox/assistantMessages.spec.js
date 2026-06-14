import assistantMessagesAPI from '../../inbox/assistantMessages';
import ApiClient from '../../ApiClient';

describe('#AssistantMessagesAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    post: vi.fn(() => Promise.resolve()),
    get: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('creates correct instance', () => {
    expect(assistantMessagesAPI).toBeInstanceOf(ApiClient);
  });

  it('#get fetches assistant messages for a conversation', () => {
    assistantMessagesAPI.get(12);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/conversations/12/assistant_messages'
    );
  });

  it('#create asks the assistant through its own endpoint', () => {
    assistantMessagesAPI.create({ conversationId: 12, question: 'Question' });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/conversations/12/assistant_messages',
      { question: 'Question' }
    );
  });

  it('#sendToCustomer sends only the assistant message id', () => {
    assistantMessagesAPI.sendToCustomer({
      conversationId: 12,
      assistantMessageId: 45,
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/conversations/12/assistant_messages/45/send_to_customer'
    );
  });
});
