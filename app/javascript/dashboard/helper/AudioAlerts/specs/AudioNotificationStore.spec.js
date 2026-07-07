import AudioNotificationStore from '../AudioNotificationStore';

describe('AudioNotificationStore', () => {
  let store;
  let audioNotificationStore;

  beforeEach(() => {
    store = {
      getters: {
        getAllStatusChats: vi.fn(),
        getSelectedChat: null,
      },
    };
    audioNotificationStore = new AudioNotificationStore(store);
  });

  describe('hasUnreadConversation', () => {
    it('should return true when there are unread conversations', () => {
      store.getters.getAllStatusChats.mockReturnValue([
        { id: 1, unread_count: 2 },
        { id: 2, unread_count: 0 },
      ]);

      expect(audioNotificationStore.hasUnreadConversation()).toBe(true);
    });

    it('should return false when there are no unread conversations', () => {
      store.getters.getAllStatusChats.mockReturnValue([
        { id: 1, unread_count: 0 },
        { id: 2, unread_count: 0 },
      ]);

      expect(audioNotificationStore.hasUnreadConversation()).toBe(false);
    });

    it('should return false when there are no conversations', () => {
      store.getters.getAllStatusChats.mockReturnValue([]);

      expect(audioNotificationStore.hasUnreadConversation()).toBe(false);
    });

    it('should call getAllStatusChats with correct parameters', () => {
      store.getters.getAllStatusChats.mockReturnValue([]);
      audioNotificationStore.hasUnreadConversation();

      expect(store.getters.getAllStatusChats).toHaveBeenCalledWith({
        status: 'open',
      });
    });
  });

  describe('isNotificationFromCurrentConversation', () => {
    it('should return true when notification is from selected chat', () => {
      store.getters.getSelectedChat = { id: 6179 };
      const notification = { primary_actor: { id: 6179 } };

      expect(
        audioNotificationStore.isNotificationFromCurrentConversation(
          notification
        )
      ).toBe(true);
    });

    it('should return false when notification is from different chat', () => {
      store.getters.getSelectedChat = { id: 6179 };
      const notification = { primary_actor: { id: 1337 } };

      expect(
        audioNotificationStore.isNotificationFromCurrentConversation(
          notification
        )
      ).toBe(false);
    });

    it('should return false when no chat is selected', () => {
      store.getters.getSelectedChat = null;
      const notification = { primary_actor: { id: 6179 } };

      expect(
        audioNotificationStore.isNotificationFromCurrentConversation(
          notification
        )
      ).toBe(false);
    });
  });
});
