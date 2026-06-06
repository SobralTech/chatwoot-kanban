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
  let wrapper;

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

    wrapper = shallowMount(ConversationBox, {
      attachTo: document.body,
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
          FluentIcon: true,
        },
      },
    });

    return wrapper;
  };

  beforeEach(() => {
    currentChat = { id: 1, inbox_id: 2 };
    MessageApi.searchMessages.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('renders the conversation messages view when a conversation exists', () => {
    createWrapper();

    expect(wrapper.findComponent({ name: 'MessagesView' }).exists()).toBe(true);
  });

  it('opens search with Ctrl+F when a conversation exists', async () => {
    createWrapper();
    const event = new KeyboardEvent('keydown', {
      key: 'f',
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });

    document.dispatchEvent(event);
    await nextTick();

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.vm.isConversationSearchOpen).toBe(true);
  });

  it('opens search with Cmd+F when a conversation exists', async () => {
    createWrapper();
    const event = new KeyboardEvent('keydown', {
      key: 'f',
      metaKey: true,
      bubbles: true,
      cancelable: true,
    });

    document.dispatchEvent(event);
    await nextTick();

    expect(event.defaultPrevented).toBe(true);
    expect(wrapper.vm.isConversationSearchOpen).toBe(true);
  });

  it('does not hijack shortcut without a selected conversation', async () => {
    currentChat = {};
    createWrapper();
    const event = new KeyboardEvent('keydown', {
      key: 'f',
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });

    document.dispatchEvent(event);
    await nextTick();

    expect(event.defaultPrevented).toBe(false);
    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
  });

  it('does not hijack shortcut from unrelated focused inputs', async () => {
    createWrapper();
    const input = document.createElement('input');
    document.body.appendChild(input);
    input.focus();
    const event = new KeyboardEvent('keydown', {
      key: 'f',
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });

    input.dispatchEvent(event);
    await nextTick();

    expect(event.defaultPrevented).toBe(false);
    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
  });

  it('focuses search input after opening', async () => {
    createWrapper();

    wrapper.vm.openConversationSearch();
    await nextTick();

    expect(document.activeElement).toBe(
      wrapper.find('[data-testid="conversation-search-input"]').element
    );
  });

  it('resets results without API call for a blank query', async () => {
    createWrapper();
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
    createWrapper();

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
    createWrapper();

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
    createWrapper();

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
    createWrapper();

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
    createWrapper();
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
    createWrapper();

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
    createWrapper();
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

  it('triggers debounced backend search from input', async () => {
    vi.useFakeTimers();
    MessageApi.searchMessages.mockResolvedValue({
      data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
    });
    createWrapper();
    wrapper.vm.openConversationSearch();
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .setValue('billing');

    expect(MessageApi.searchMessages).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(300);

    expect(MessageApi.searchMessages).toHaveBeenCalledWith(1, {
      q: 'billing',
      signal: expect.any(AbortSignal),
    });
  });

  it('resets debounced blank input without API call', async () => {
    vi.useFakeTimers();
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 1 };
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .setValue('');
    await vi.advanceTimersByTimeAsync(300);

    expect(MessageApi.searchMessages).not.toHaveBeenCalled();
    expect(wrapper.vm.conversationSearchResults).toEqual([]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({});
  });

  it('renders the current result counter', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 14 };
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    expect(
      wrapper.find('[data-testid="conversation-search-counter"]').text()
    ).toBe('1/14');
  });

  it('next button updates active index', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-next"]')
      .trigger('click');

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(1);
  });

  it('previous button updates active index', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-previous"]')
      .trigger('click');

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(1);
  });

  it('Enter selects the next result', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Enter' });

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(1);
  });

  it('Shift+Enter selects the previous result', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Enter', shiftKey: true });

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(1);
  });

  it('Escape closes and resets search', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.conversationSearchResults = [{ id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 1 };
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Escape' });

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
    expect(wrapper.vm.conversationSearchQuery).toBe('');
    expect(wrapper.vm.conversationSearchResults).toEqual([]);
  });

  it('close button closes and resets search', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.conversationSearchResults = [{ id: 1 }];
    wrapper.vm.conversationSearchMeta = { total_count: 1 };
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-close"]')
      .trigger('click');

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
    expect(wrapper.vm.conversationSearchQuery).toBe('');
    expect(wrapper.vm.conversationSearchResults).toEqual([]);
    expect(wrapper.vm.conversationSearchMeta).toEqual({});
  });
});
