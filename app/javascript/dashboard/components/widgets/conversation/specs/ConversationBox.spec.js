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
  let mergeConversationMessageWindow;

  const translations = {
    'CONVERSATION.SEARCH.MESSAGE_UNAVAILABLE': 'Message unavailable',
    'CONVERSATION.SEARCH.FAILED_TO_LOAD_MESSAGE': 'Failed to load message',
  };

  const createWrapper = () => {
    mergeConversationMessageWindow ||= vi.fn().mockResolvedValue();
    store = createStore({
      getters: {
        getSelectedChat: () => currentChat,
      },
      actions: {
        'conversationLabels/get': vi.fn(),
        'dashboardApps/get': vi.fn(),
        'inboxAssignableAgents/fetch': vi.fn(),
        mergeConversationMessageWindow,
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
          $t: key => translations[key] || key,
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
    currentChat = { id: 1, inbox_id: 2, messages: [] };
    mergeConversationMessageWindow = null;
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
    currentChat.messages = [{ id: 1 }, { id: 2 }];
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
    currentChat.messages = [{ id: 1 }, { id: 2 }];
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
    currentChat.messages = [{ id: 1 }, { id: 2 }];
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
    currentChat.messages = [{ id: 1 }, { id: 2 }];
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

  it('does not request a message window for a loaded result', async () => {
    currentChat.messages = [{ id: 2 }];
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(0);
    expect(mergeConversationMessageWindow).not.toHaveBeenCalled();
  });

  it('dispatches message window merge for an unloaded result', async () => {
    currentChat.messages = [{ id: 1 }];
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);

    expect(mergeConversationMessageWindow).toHaveBeenCalledWith(
      expect.anything(),
      {
        conversationId: 1,
        around: 2,
        before_limit: 20,
        after_limit: 20,
        signal: expect.any(AbortSignal),
      }
    );
  });

  it('scrolls to the merged result after render', async () => {
    const scrollIntoView = vi.fn();
    const messageElement = document.createElement('div');
    messageElement.id = 'message2';
    messageElement.scrollIntoView = scrollIntoView;
    document.body.appendChild(messageElement);
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);

    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'nearest',
    });
  });

  it('preserves existing messages and allMessagesLoaded while loading a window', async () => {
    currentChat.messages = [{ id: 1 }];
    currentChat.allMessagesLoaded = true;
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);

    expect(currentChat.messages).toEqual([{ id: 1 }]);
    expect(currentChat.allMessagesLoaded).toBe(true);
  });

  it('shows message unavailable for a missing anchor', async () => {
    mergeConversationMessageWindow = vi.fn().mockRejectedValue({
      response: { status: 404 },
    });
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);
    await nextTick();

    expect(wrapper.vm.conversationSearchNavigationError).toBe(
      'Message unavailable'
    );
    expect(
      wrapper.find('[data-testid="conversation-search-error"]').text()
    ).toBe('Message unavailable');
  });

  it('shows failed to load message for ordinary failures', async () => {
    mergeConversationMessageWindow = vi
      .fn()
      .mockRejectedValue(new Error('Boom'));
    createWrapper();
    wrapper.vm.openConversationSearch();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);
    await nextTick();

    expect(wrapper.vm.conversationSearchNavigationError).toBe(
      'Failed to load message'
    );
    expect(
      wrapper.find('[data-testid="conversation-search-error"]').text()
    ).toBe('Failed to load message');
  });

  it('aborts previous result navigation when a newer result is selected', async () => {
    let firstSignal;
    mergeConversationMessageWindow = vi.fn((_, payload) => {
      if (!firstSignal) firstSignal = payload.signal;
      return new Promise(() => {});
    });
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 3 }];

    wrapper.vm.selectConversationSearchResult(0);
    await nextTick();
    wrapper.vm.selectConversationSearchResult(1);
    await nextTick();

    expect(firstSignal.aborted).toBe(true);
  });

  it('does not scroll for stale result navigation responses', async () => {
    let resolveFirst;
    const scrollIntoView = vi.fn();
    const messageElement = document.createElement('div');
    messageElement.id = 'message2';
    messageElement.scrollIntoView = scrollIntoView;
    document.body.appendChild(messageElement);
    mergeConversationMessageWindow = vi
      .fn()
      .mockReturnValueOnce(
        new Promise(resolve => {
          resolveFirst = resolve;
        })
      )
      .mockReturnValueOnce(new Promise(() => {}));
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 3 }];

    const firstNavigation = wrapper.vm.selectConversationSearchResult(0);
    await nextTick();
    wrapper.vm.selectConversationSearchResult(1);
    await nextTick();

    resolveFirst();
    await firstNavigation;

    expect(scrollIntoView).not.toHaveBeenCalled();
  });

  it('aborts pending result navigation when closing search', async () => {
    let signal;
    mergeConversationMessageWindow = vi.fn((_, payload) => {
      signal = payload.signal;
      return new Promise(() => {});
    });
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    wrapper.vm.selectConversationSearchResult(0);
    await nextTick();
    wrapper.vm.closeConversationSearch();

    expect(signal.aborted).toBe(true);
  });

  it('aborts pending result navigation when conversation changes', async () => {
    let signal;
    mergeConversationMessageWindow = vi.fn((_, payload) => {
      signal = payload.signal;
      return new Promise(() => {});
    });
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    wrapper.vm.selectConversationSearchResult(0);
    await nextTick();
    currentChat = { id: 2, inbox_id: 3, messages: [] };
    await store.hotUpdate({
      getters: {
        getSelectedChat: () => currentChat,
      },
    });
    await nextTick();

    expect(signal.aborted).toBe(true);
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
