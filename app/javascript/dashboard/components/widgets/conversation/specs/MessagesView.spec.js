import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import MessagesView from '../MessagesView.vue';

vi.mock('@vueuse/core', () => ({
  useElementSize: () => ({ height: 0 }),
}));

vi.mock('dashboard/composables/useLabelSuggestions', () => ({
  useLabelSuggestions: () => ({
    captainTasksEnabled: false,
    isLabelSuggestionFeatureEnabled: false,
    getLabelSuggestions: vi.fn(() => []),
  }),
}));

describe('MessagesView', () => {
  it('passes conversation search props to MessageList', async () => {
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem: vi.fn(() => null),
        setItem: vi.fn(),
        removeItem: vi.fn(),
      },
      configurable: true,
    });

    const store = createStore({
      getters: {
        getSelectedChat: () => ({
          id: 1,
          inbox_id: 1,
          messages: [],
          can_reply: true,
          agent_last_seen_at: 0,
          labels: [],
        }),
        getCurrentUserID: () => 1,
        getAllMessagesLoaded: () => true,
        getCurrentAccountId: () => 1,
        'inboxes/getInbox': () => () => ({}),
        'inboxes/getInstagramInboxByInstagramId': () => () => null,
        'conversationTypingStatus/getUserList': () => () => [],
      },
      actions: {
        fetchAllAttachments: vi.fn(),
      },
    });

    const wrapper = shallowMount(MessagesView, {
      props: {
        conversationSearchQuery: 'billing',
        activeConversationSearchResultId: 1,
      },
      global: {
        plugins: [store],
        mocks: {
          $t: key => key,
          $route: { query: {} },
        },
        stubs: {
          MessageList: {
            name: 'MessageList',
            template: '<div class="conversation-panel" />',
          },
          ReplyBox: true,
          Banner: true,
          ConversationLabelSuggestion: true,
          Spinner: true,
          ResizableEditorWrapper: { template: '<div><slot /></div>' },
        },
      },
    });

    const messageList = wrapper.findComponent({ name: 'MessageList' });

    expect(messageList.attributes('conversation-search-query')).toBe('billing');
    expect(messageList.attributes('active-conversation-search-result-id')).toBe(
      '1'
    );
  });
});
