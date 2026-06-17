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

  describe('#UPDATE_CONVERSATION_PIN', () => {
    it('sets personal_pinned_at when pinType is personal', () => {
      const state = {
        allConversations: [
          { id: 1, personal_pinned_at: null, account_pinned_at: null },
        ],
      };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 1,
        pinType: 'personal',
        pinnedAt: 1700000000,
      });
      expect(state.allConversations[0].personal_pinned_at).toBe(1700000000);
      expect(state.allConversations[0].account_pinned_at).toBeNull();
    });

    it('sets account_pinned_at when pinType is account', () => {
      const state = {
        allConversations: [
          { id: 1, personal_pinned_at: null, account_pinned_at: null },
        ],
      };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 1,
        pinType: 'account',
        pinnedAt: 1700000000,
      });
      expect(state.allConversations[0].account_pinned_at).toBe(1700000000);
      expect(state.allConversations[0].personal_pinned_at).toBeNull();
    });

    it('sets pinnedAt to null when unpinning', () => {
      const state = {
        allConversations: [
          { id: 1, personal_pinned_at: 1700000000, account_pinned_at: null },
        ],
      };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 1,
        pinType: 'personal',
        pinnedAt: null,
      });
      expect(state.allConversations[0].personal_pinned_at).toBeNull();
    });

    it('does nothing if conversation is not found', () => {
      const state = { allConversations: [{ id: 2, personal_pinned_at: null }] };
      mutations[types.UPDATE_CONVERSATION_PIN](state, {
        conversationId: 999,
        pinType: 'personal',
        pinnedAt: 1700000000,
      });
      expect(state.allConversations[0].personal_pinned_at).toBeNull();
    });
  });

  describe('#UPDATE_CONVERSATION — personal_pinned_at protection', () => {
    const baseState = () => ({
      allConversations: [
        {
          id: 1,
          updated_at: 100,
          personal_pinned_at: 1700000000,
          account_pinned_at: null,
          messages: [],
        },
      ],
      selectedChatId: null,
      conversationFilters: {},
    });

    it('preserves personal_pinned_at when broadcast data omits the key', () => {
      const state = baseState();
      mutations[types.UPDATE_CONVERSATION](state, {
        id: 1,
        updated_at: 200,
        account_pinned_at: 1700001000,
        messages: [],
      });
      expect(state.allConversations[0].personal_pinned_at).toBe(1700000000);
      expect(state.allConversations[0].account_pinned_at).toBe(1700001000);
    });

    it('preserves personal_pinned_at when broadcast data has it as null', () => {
      const state = baseState();
      mutations[types.UPDATE_CONVERSATION](state, {
        id: 1,
        updated_at: 200,
        personal_pinned_at: null,
        messages: [],
      });
      expect(state.allConversations[0].personal_pinned_at).toBe(1700000000);
    });

    it('updates personal_pinned_at when broadcast explicitly provides a value', () => {
      const state = baseState();
      mutations[types.UPDATE_CONVERSATION](state, {
        id: 1,
        updated_at: 200,
        personal_pinned_at: 1700002000,
        messages: [],
      });
      expect(state.allConversations[0].personal_pinned_at).toBe(1700002000);
    });
  });
});
