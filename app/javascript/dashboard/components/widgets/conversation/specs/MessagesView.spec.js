import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';
import MessagesView from '../MessagesView.vue';
import { CONTACT_CONVERSATION_NAVIGATION } from 'dashboard/composables/useContactConversationNavigation';

vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useElementSize: () => ({ height: 0 }),
}));

vi.mock('dashboard/composables/useCampaignHistory', () => ({
  useCampaignHistory: () => ({
    isCampaignHistoryReady: true,
    visibleCampaignHistory: [],
    hasMoreCampaignHistory: false,
    isCampaignHistoryLoading: false,
    loadCampaignHistory: vi.fn(),
  }),
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
        provide: {
          [CONTACT_CONVERSATION_NAVIGATION]: {
            olderConversation: ref(null),
            newerConversation: ref(null),
            isReadingHistory: ref(false),
            latestConversation: ref(null),
            leaveReadingMode: vi.fn(),
            openConversation: vi.fn(),
            buildConversationPath: vi.fn(),
          },
        },
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
