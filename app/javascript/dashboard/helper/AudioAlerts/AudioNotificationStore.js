class AudioNotificationStore {
  constructor(store) {
    this.store = store;
  }

  hasUnreadConversation = () => {
    const openConversations = this.store.getters.getAllStatusChats({
      status: 'open',
    });

    return openConversations.some(conv => conv.unread_count > 0);
  };

  isNotificationFromCurrentConversation = notification => {
    return (
      this.store.getters.getSelectedChat?.id === notification.primary_actor?.id
    );
  };
}

export default AudioNotificationStore;
