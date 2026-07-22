import { describe, it, expect, vi, beforeEach } from 'vitest';
import actions from '../actions';
import types from '../../../mutation-types';
import ConversationApi from '../../../../api/inbox/conversation';

vi.mock('../../../../api/inbox/conversation', () => ({
  default: {
    show: vi.fn(),
  },
}));

describe('conversation actions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('#getConversation', () => {
    const hiddenConversation = {
      id: 123,
      inbox_id: 7,
      inbox_show_in_all_conversations: false,
      meta: { sender: { id: 1, name: 'Jane' } },
    };

    it('does not upsert hidden inbox conversations into All after fetch without relying on inbox cache', async () => {
      ConversationApi.show.mockResolvedValue({ data: hiddenConversation });
      const commit = vi.fn();

      await actions.getConversation(
        {
          commit,
          state: { conversationFilters: { conversationView: 'all' } },
          rootGetters: {
            'inboxes/getInbox': () => ({}),
          },
        },
        123
      );

      expect(commit).not.toHaveBeenCalledWith(
        types.UPSERT_CONVERSATION,
        hiddenConversation
      );
      expect(commit).toHaveBeenCalledWith(
        `contacts/${types.SET_CONTACT_ITEM}`,
        hiddenConversation.meta.sender
      );
    });

    it('allows force upsert to preserve the selected conversation', async () => {
      ConversationApi.show.mockResolvedValue({ data: hiddenConversation });
      const commit = vi.fn();

      await actions.getConversation(
        {
          commit,
          state: { conversationFilters: { conversationView: 'all' } },
          rootGetters: {
            'inboxes/getInbox': () => ({ show_in_all_conversations: false }),
          },
        },
        { conversationId: 123, forceUpsert: true }
      );

      expect(commit).toHaveBeenCalledWith(
        types.UPSERT_CONVERSATION,
        hiddenConversation
      );
    });
  });

  describe('#addMessage', () => {
    it('fetches a missing conversation; hidden All guard applies in getConversation', () => {
      const commit = vi.fn();
      const dispatch = vi.fn(() => Promise.resolve());
      const getters = { getConversationById: () => undefined };
      const message = {
        id: 1,
        conversation_id: 123,
        message_type: 0,
        conversation: { last_activity_at: 1000 },
      };

      actions.addMessage(
        { commit, dispatch, getters, rootGetters: {} },
        message
      );

      expect(dispatch).toHaveBeenCalledWith('getConversation', 123);
    });
  });
});
