import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import MessageList from '../MessageList.vue';

describe('MessageList', () => {
  const mountMessageList = props =>
    shallowMount(MessageList, {
      props: {
        currentUserId: 1,
        messages: [
          {
            id: 1,
            message_type: 0,
            status: 'sent',
            content: 'Hello billing',
            content_type: 'text',
            conversation_id: 1,
            created_at: 1710000000,
          },
        ],
        ...props,
      },
      global: {
        plugins: [
          createStore({
            getters: {
              getSelectedChat: () => ({ id: 1, messages: [] }),
            },
          }),
        ],
        stubs: {
          Message: true,
        },
      },
    });

  it('passes conversation search props to messages', () => {
    const wrapper = mountMessageList({
      conversationSearchQuery: 'billing',
      activeConversationSearchResultId: 1,
    });
    const message = wrapper.findComponent({ name: 'Message' });

    expect(message.props('conversationSearchQuery')).toBe('billing');
    expect(message.props('activeConversationSearchResultId')).toBe(1);
  });
});
