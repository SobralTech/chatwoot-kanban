import { mutations } from '../index';
import types from '../../../mutation-types';

describe('#mutations', () => {
  describe('#UPDATE_MESSAGE_CALL_STATUS', () => {
    it('does nothing if conversation is not found', () => {
      const state = { allConversations: [] };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
        callSid: 'CA123',
      });
      expect(state.allConversations).toEqual([]);
    });

    it('does nothing if no matching voice call message exists', () => {
      const state = {
        allConversations: [
          { id: 1, messages: [{ id: 1, content_type: 'text' }] },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
        callSid: 'CA123',
      });
      expect(state.allConversations[0].messages[0]).toEqual({
        id: 1,
        content_type: 'text',
      });
    });

    it('updates only the voice call message matching the given callSid', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [
              {
                id: 1,
                content_type: 'voice_call',
                call: { provider_call_id: 'CA111', status: 'ringing' },
              },
              {
                id: 2,
                content_type: 'voice_call',
                call: { provider_call_id: 'CA222', status: 'ringing' },
              },
            ],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'in-progress',
        callSid: 'CA111',
      });
      expect(state.allConversations[0].messages[0].call.status).toBe(
        'in-progress'
      );
      expect(state.allConversations[0].messages[1].call.status).toBe('ringing');
    });

    it('preserves existing call fields when updating status', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [
              {
                id: 1,
                content_type: 'voice_call',
                call: {
                  provider_call_id: 'CA123',
                  status: 'ringing',
                  direction: 'incoming',
                  duration_seconds: null,
                },
              },
            ],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'in-progress',
        callSid: 'CA123',
      });
      expect(state.allConversations[0].messages[0].call).toEqual({
        provider_call_id: 'CA123',
        status: 'in-progress',
        direction: 'incoming',
        duration_seconds: null,
      });
    });

    it('handles empty messages array', () => {
      const state = {
        allConversations: [{ id: 1, messages: [] }],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'ringing',
        callSid: 'CA123',
      });
      expect(state.allConversations[0].messages).toEqual([]);
    });

    it('does nothing if matching message has no call object yet', () => {
      const state = {
        allConversations: [
          {
            id: 1,
            messages: [
              {
                id: 1,
                content_type: 'voice_call',
                call: { provider_call_id: 'CA-OTHER' },
              },
            ],
          },
        ],
      };
      mutations[types.UPDATE_MESSAGE_CALL_STATUS](state, {
        conversationId: 1,
        callStatus: 'completed',
        callSid: 'CA-MISSING',
      });
      expect(state.allConversations[0].messages[0].call).toEqual({
        provider_call_id: 'CA-OTHER',
      });
    });
  });

  describe('#UPSERT_CONVERSATION', () => {
    it('adds a conversation that is not present in allConversations, regardless of conversationFilters', () => {
      const state = {
        allConversations: [{ id: 1 }, { id: 2 }],
        conversationFilters: { conversationType: undefined },
      };
      mutations[types.UPSERT_CONVERSATION](state, {
        id: 33,
        updated_at: 1700000000,
      });
      expect(state.allConversations.map(c => c.id)).toEqual([1, 2, 33]);
    });

    it('replaces the existing conversation when it is already present', () => {
      const state = {
        allConversations: [{ id: 33, status: 'open', updated_at: 1000 }],
        conversationFilters: {},
      };
      mutations[types.UPSERT_CONVERSATION](state, {
        id: 33,
        status: 'resolved',
        updated_at: 2000,
        messages: [{ id: 1 }],
      });
      expect(state.allConversations[0].status).toBe('resolved');
    });

    it('ignores out of order updates for an existing conversation', () => {
      const state = {
        allConversations: [{ id: 33, status: 'open', updated_at: 2000 }],
        conversationFilters: {},
      };
      mutations[types.UPSERT_CONVERSATION](state, {
        id: 33,
        status: 'resolved',
        updated_at: 1000,
      });
      expect(state.allConversations[0].status).toBe('open');
    });
  });

  describe('#UPDATE_CONVERSATION_PIN', () => {
    it('sets account_pinned_at', () => {
      const state = {
        allConversations: [{ id: 1, account_pinned_at: null }],
      };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 1,
        pinnedAt: 1700000000,
      });
      expect(state.allConversations[0].account_pinned_at).toBe(1700000000);
    });

    it('sets pinnedAt to null when unpinning', () => {
      const state = {
        allConversations: [{ id: 1, account_pinned_at: 1700000000 }],
      };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 1,
        pinnedAt: null,
      });
      expect(state.allConversations[0].account_pinned_at).toBeNull();
    });

    it('does nothing if conversation is not found', () => {
      const state = { allConversations: [{ id: 2, account_pinned_at: null }] };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 999,
        pinnedAt: 1700000000,
      });
      expect(state.allConversations[0].account_pinned_at).toBeNull();
    });
  });
});
