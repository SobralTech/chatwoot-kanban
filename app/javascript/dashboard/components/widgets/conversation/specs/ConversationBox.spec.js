import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';

import ConversationBox from '../ConversationBox.vue';
import MessageApi from 'dashboard/api/inbox/message';

vi.mock('dashboard/api/inbox/message', () => ({
  default: {
    searchMessages: vi.fn(),
  },
}));

describe('ConversationBox', () => {
  let currentChat;
  let store;

  const createWrapper = () => {
    store = createStore({
      getters: {
        getSelectedChat: () => currentChat,
      },
      actions: {
        'conversationLabels/get': vi.fn(),
        'dashboardApps/get': vi.fn(),
        'inboxAssignableAgents/fetch': vi.fn(),
      },
      modules: {
        dashboardApps: {
          namespaced: true,
          getters: {
            getRecords: () => [],
          },
        },
      },
    });

    return shallowMount(ConversationBox, {
      global: {
        plugins: [store],
        mocks: {
          $t: key => key,
        },
        stubs: {
          ConversationHeader: true,
          MessagesView: true,
          EmptyState: true,
          DashboardAppFrame: true,
          WootTabs: true,
          WootTabsItem: true,
        },
      },
    });
  };

  beforeEach(() => {
    currentChat = { id: 1, inbox_id: 2 };
    MessageApi.searchMessages.mockReset();
  });

  it('renders the conversation messages view when a conversation exists', () => {
    const wrapper = createWrapper();

    expect(wrapper.findComponent({ name: 'MessagesView' }).exists()).toBe(true);
  });

  it('resets results without API call for a blank query', async () => {
    const wrapper = createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 1 };

    await wrapper.vm.searchConversationMessages('   ');

    expect(MessageApi.searchMessages).not.toHaveBeenCalled();
    expect(wrapper.vm.conversationSearchResults).toEqual([]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({});
  });

  it('calls search endpoint for a valid query', async () => {
    MessageApi.searchMessages.mockResolvedValue({
      data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
    });
    const wrapper = createWrapper();

    await wrapper.vm.searchConversationMessages(' billing ');

    expect(MessageApi.searchMessages).toHaveBeenCalledWith(1, {
      q: 'billing',
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.vm.conversationSearchResults).toEqual([{ id: 1 }]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({ total_count: 1 });
  });

  it('tracks loading state while searching', async () => {
    let resolveSearch;
    MessageApi.searchMessages.mockReturnValue(
      new Promise(resolve => {
        resolveSearch = resolve;
      })
    );
    const wrapper = createWrapper();

    const searchPromise = wrapper.vm.searchConversationMessages('billing');
    await nextTick();

    expect(wrapper.vm.isSearchingConversationMessages).toBe(true);

    resolveSearch({ data: { payload: [], meta: {} } });
    await searchPromise;

    expect(wrapper.vm.isSearchingConversationMessages).toBe(false);
  });

  it('stores API errors', async () => {
    const error = new Error('Search failed');
    MessageApi.searchMessages.mockRejectedValue(error);
    const wrapper = createWrapper();

    await wrapper.vm.searchConversationMessages('billing');

    expect(wrapper.vm.conversationSearchError).toBe(error);
  });

  it('replaces previous results for a new query', async () => {
    MessageApi.searchMessages
      .mockResolvedValueOnce({
        data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
      })
      .mockResolvedValueOnce({
        data: { payload: [{ id: 2 }], meta: { total_count: 1 } },
      });
    const wrapper = createWrapper();

    await wrapper.vm.searchConversationMessages('billing');
    await wrapper.vm.searchConversationMessages('refund');

    expect(wrapper.vm.conversationSearchResults).toEqual([{ id: 2 }]);
    expect(wrapper.vm.conversationSearchQuery).toBe('refund');
  });

  it('appends load more results and updates meta', async () => {
    MessageApi.searchMessages.mockResolvedValue({
      data: {
        payload: [{ id: 1 }],
        meta: { total_count: 2, limit: 20, has_more: false },
      },
    });
    const wrapper = createWrapper();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.conversationSearchResults = [{ id: 2 }];
    wrapper.vm.conversationSearchMeta = {
      total_count: 2,
      limit: 20,
      has_more: true,
      next_before_id: 2,
    };

    await wrapper.vm.loadMoreConversationSearchResults();

    expect(MessageApi.searchMessages).toHaveBeenCalledWith(1, {
      q: 'billing',
      limit: 20,
      before_id: 2,
    });
    expect(wrapper.vm.conversationSearchResults).toEqual([
      { id: 2 },
      { id: 1 },
    ]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({
      total_count: 2,
      limit: 20,
      has_more: false,
    });
  });

  it('ignores stale search responses', async () => {
    let resolveFirstSearch;
    MessageApi.searchMessages
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveFirstSearch = resolve;
        })
      )
      .mockResolvedValueOnce({
        data: { payload: [{ id: 2 }], meta: { total_count: 1 } },
      });
    const wrapper = createWrapper();

    const firstSearchPromise = wrapper.vm.searchConversationMessages('billing');
    await wrapper.vm.searchConversationMessages('refund');

    resolveFirstSearch({
      data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
    });
    await firstSearchPromise;

    expect(wrapper.vm.conversationSearchResults).toEqual([{ id: 2 }]);
    expect(wrapper.vm.conversationSearchQuery).toBe('refund');
  });

  it('resets search state when selected conversation changes', async () => {
    const wrapper = createWrapper();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.conversationSearchResults = [{ id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 1 };
    currentChat = { id: 2, inbox_id: 3 };

    await store.hotUpdate({
      getters: {
        getSelectedChat: () => currentChat,
      },
    });
    await nextTick();

    expect(wrapper.vm.conversationSearchQuery).toBe('');
    expect(wrapper.vm.conversationSearchResults).toEqual([]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({});
  });
});
