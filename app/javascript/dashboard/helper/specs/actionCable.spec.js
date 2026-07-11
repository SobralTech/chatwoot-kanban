import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const { mockUseAlert } = vi.hoisted(() => ({
  mockUseAlert: vi.fn(),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mockUseAlert,
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

global.chatwootConfig = {
  websocketURL: 'wss://test.chatwoot.com',
};

const KANBAN_EVENTS = [
  'kanban.board.updated',
  'kanban.stage.created',
  'kanban.stage.updated',
  'kanban.stage.deleted',
  'kanban.stage.reordered',
  'kanban.card.created',
  'kanban.card.updated',
  'kanban.card.deleted',
  'kanban.card.reordered',
];

describe('ActionCableConnector - Copilot Tests', () => {
  let store;
  let actionCable;
  let mockDispatch;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    store = {
      $store: {
        dispatch: mockDispatch,
        state: {
          conversations: {
            conversationFilters: {},
          },
        },
        getters: {
          getCurrentAccountId: 1,
          'accounts/isFeatureEnabledonAccount': vi.fn(() => true),
          getChatListFilters: {},
          getSelectedChat: null,
          'inboxes/getInboxes': [],
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });

  describe('all conversations inbox visibility', () => {
    beforeEach(() => {
      store.$store.getters.getChatListFilters = { conversationView: 'all' };
      store.$store.getters['inboxes/getInboxes'] = [
        { id: 1, show_in_all_conversations: true },
        { id: 2, show_in_all_conversations: false },
      ];
    });

    it('does not insert hidden inbox realtime conversations but refreshes stats', () => {
      const conversation = { id: 10, inbox_id: 2 };

      actionCable.onConversationCreated(conversation);

      expect(mockDispatch).not.toHaveBeenCalledWith(
        'addConversation',
        conversation
      );
      expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
    });

    it('does not update hidden inbox realtime conversations but refreshes stats', () => {
      const conversation = { id: 10, inbox_id: 2 };

      actionCable.onConversationUpdated(conversation);

      expect(mockDispatch).not.toHaveBeenCalledWith(
        'updateConversation',
        conversation
      );
      expect(emitter.emit).toHaveBeenCalledWith('fetch_conversation_stats');
    });

    it('resets pagination and refetches All once when eligible inboxes change', async () => {
      let inboxes = [{ id: 1, show_in_all_conversations: true }];
      store.$store.getters['inboxes/getInboxes'] = inboxes;
      mockDispatch.mockImplementation(action => {
        if (action === 'inboxes/revalidate') {
          inboxes = [
            { id: 1, show_in_all_conversations: true },
            { id: 2, show_in_all_conversations: true },
          ];
          store.$store.getters['inboxes/getInboxes'] = inboxes;
        }
        return Promise.resolve();
      });

      await actionCable.onCacheInvalidate({ cache_keys: {} });

      expect(mockDispatch).toHaveBeenCalledWith('conversationPage/reset');
      expect(mockDispatch).toHaveBeenCalledWith('updateChatListFilters', {
        page: 1,
        conversationView: 'all',
      });
      expect(
        mockDispatch.mock.calls.filter(
          ([action]) => action === 'fetchAllConversations'
        )
      ).toHaveLength(1);
    });

    it('does not consider the app on All after ChatList clears all-view state', () => {
      store.$store.getters.getChatListFilters = { conversationView: undefined };

      expect(actionCable.isOnAllConversationsView()).toBe(false);
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });
  describe('copilot event handlers', () => {
    it('should register the copilot.message.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'copilot.message.created'
      );
      expect(actionCable.events['copilot.message.created']).toBe(
        actionCable.onCopilotMessageCreated
      );
    });

    it('should handle the copilot.message.created event through the ActionCable system', () => {
      const copilotData = {
        id: 2,
        content: 'This is a copilot message from ActionCable',
        conversation_id: 456,
        created_at: '2025-05-27T15:58:04-06:00',
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'copilot.message.created',
        data: copilotData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'copilotMessages/upsert',
        copilotData
      );
    });
  });

  describe('conversation unread count event handlers', () => {
    it('should register the conversation.unread_count_changed event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'conversation.unread_count_changed'
      );
      expect(actionCable.events['conversation.unread_count_changed']).toBe(
        actionCable.onConversationUnreadCountChanged
      );
    });

    it('should refetch unread counts when unread count changes', () => {
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledWith('conversationUnreadCounts/get');
    });

    it('does not refetch unread counts when unread count feature is disabled', () => {
      store.$store.getters[
        'accounts/isFeatureEnabledonAccount'
      ].mockReturnValue(false);

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).not.toHaveBeenCalledWith(
        'conversationUnreadCounts/get'
      );
    });

    it('should throttle unread count refetches for repeated events', () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledTimes(1);

      vi.advanceTimersByTime(4999);
      expect(mockDispatch).toHaveBeenCalledTimes(1);

      vi.advanceTimersByTime(1);
      expect(mockDispatch).toHaveBeenCalledTimes(2);
      expect(mockDispatch).toHaveBeenLastCalledWith(
        'conversationUnreadCounts/get'
      );
    });

    it('clears pending unread count refetch before immediate refetch', () => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));

      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      vi.advanceTimersByTime(1000);
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      vi.setSystemTime(new Date('2026-01-01T00:00:06Z'));
      actionCable.onReceived({
        event: 'conversation.unread_count_changed',
        data: { account_id: 1 },
      });

      expect(mockDispatch).toHaveBeenCalledTimes(2);

      vi.advanceTimersByTime(4000);
      expect(mockDispatch).toHaveBeenCalledTimes(2);
    });
  });

  describe('conversation access revoked event handlers', () => {
    it('registers the conversation.access_revoked event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'conversation.access_revoked'
      );
      expect(actionCable.events['conversation.access_revoked']).toBe(
        actionCable.onConversationAccessRevoked
      );
    });

    it('removes the conversation when access is revoked', () => {
      const payload = { account_id: 1, id: 42 };
      store.$store.getters.getSelectedChat = { id: 99 };

      actionCable.onReceived({
        event: 'conversation.access_revoked',
        data: payload,
      });

      expect(mockDispatch).toHaveBeenCalledWith(
        'handleConversationAccessRevoked',
        payload
      );
      expect(mockUseAlert).not.toHaveBeenCalled();
    });

    it('shows unavailable alert when the revoked conversation is open', () => {
      const payload = { account_id: 1, id: 42 };
      store.$store.getters.getSelectedChat = { id: 42 };

      actionCable.onReceived({
        event: 'conversation.access_revoked',
        data: payload,
      });

      expect(mockDispatch).toHaveBeenCalledWith(
        'handleConversationAccessRevoked',
        payload
      );
      expect(mockUseAlert).toHaveBeenCalledWith(
        'CONVERSATION.ACCESS_CONTROL.CONVERSATION_UNAVAILABLE',
        { usei18n: true }
      );
    });
  });

  describe('kanban event handlers', () => {
    it.each(KANBAN_EVENTS)(
      'should register the %s event handler',
      eventName => {
        expect(Object.keys(actionCable.events)).toContain(eventName);
        expect(actionCable.events[eventName]).toEqual(expect.any(Function));
      }
    );

    it.each(KANBAN_EVENTS)(
      'should route %s through the dashboard bus',
      eventName => {
        const data = {
          account_id: 1,
          board_id: 10,
          stage_id: 20,
          card_id: 30,
        };

        actionCable.onReceived({ event: eventName, data });

        expect(emitter.emit).toHaveBeenCalledWith(
          BUS_EVENTS.KANBAN_REALTIME_EVENT,
          { event: eventName, data }
        );
        expect(mockDispatch).not.toHaveBeenCalled();
      }
    );

    it('should preserve card reorder payload unchanged', () => {
      const data = {
        account_id: 1,
        board_id: 10,
        card_id: 30,
        source_stage_id: 20,
        target_stage_id: 21,
      };

      actionCable.onReceived({ event: 'kanban.card.reordered', data });

      expect(emitter.emit).toHaveBeenCalledWith(
        BUS_EVENTS.KANBAN_REALTIME_EVENT,
        { event: 'kanban.card.reordered', data }
      );
    });

    it('should ignore kanban events for other accounts', () => {
      actionCable.onReceived({
        event: 'kanban.card.created',
        data: { account_id: 2, board_id: 10, stage_id: 20, card_id: 30 },
      });

      expect(emitter.emit).not.toHaveBeenCalledWith(
        BUS_EVENTS.KANBAN_REALTIME_EVENT,
        expect.anything()
      );
      expect(mockDispatch).not.toHaveBeenCalled();
    });

    it('should leave unknown events unchanged', () => {
      actionCable.onReceived({
        event: 'kanban.unknown',
        data: { account_id: 1, board_id: 10 },
      });

      expect(emitter.emit).not.toHaveBeenCalled();
      expect(mockDispatch).not.toHaveBeenCalled();
    });
  });
});
