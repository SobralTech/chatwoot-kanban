import ConversationApi from '../inbox/conversation';

describe('#ConversationAccessUsersAPI', () => {
  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      put: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      Object.defineProperty(ConversationApi, 'accountIdFromRoute', {
        get: () => '1',
        configurable: true,
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#getAccessUsers', () => {
      ConversationApi.getAccessUsers(42);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/conversations/42/access_users'
      );
    });

    it('#getEligibleAccessUsers', () => {
      ConversationApi.getEligibleAccessUsers(42);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/conversations/42/access_users/eligible'
      );
    });

    it('#updateAccessUsers', () => {
      ConversationApi.updateAccessUsers({
        conversationId: 42,
        userIds: [1, 2],
      });

      expect(axiosMock.put).toHaveBeenCalledWith(
        '/api/v1/accounts/1/conversations/42/access_users',
        {
          user_ids: [1, 2],
        }
      );
    });
  });
});
