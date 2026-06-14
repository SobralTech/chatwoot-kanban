import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';

import ConversationSearchPanel from '../ConversationSearchPanel.vue';
import MessageApi from 'dashboard/api/inbox/message';
import enConversationMessages from '../../../../i18n/locale/en/conversation.json';
import ptBRConversationMessages from '../../../../i18n/locale/pt_BR/conversation.json';

vi.mock('dashboard/api/inbox/message', () => ({
  default: {
    searchMessages: vi.fn(),
  },
}));

describe('ConversationSearchPanel', () => {
  let currentChat;
  let store;
  let wrapper;
  let mergeConversationMessageWindow;

  const translations = {
    'CONVERSATION.SEARCH.MESSAGE_UNAVAILABLE': 'Message unavailable',
    'CONVERSATION.SEARCH.FAILED_TO_LOAD_MESSAGE': 'Failed to load message',
    'CONVERSATION.SEARCH.FAILED_TO_SEARCH_MESSAGES':
      'Failed to search messages',
    'CONVERSATION.SEARCH.NO_RESULTS': 'No results',
    'CONVERSATION.SEARCH.CONTACT': 'Contact',
    'CONVERSATION.SEARCH.AGENT': 'Agent',
    'CONVERSATION.SEARCH.LOAD_MORE': 'Load more results',
    'CONVERSATION.SEARCH.PANEL_TITLE': 'Search messages',
    'CONVERSATION.SEARCH.SEARCH_IN_CONVERSATION': 'Search in conversation',
    'CONVERSATION.SEARCH.CLEAR_SEARCH': 'Clear search',
  };

  const createWrapper = () => {
    mergeConversationMessageWindow ||= vi.fn().mockResolvedValue();
    store = createStore({
      getters: {
        getSelectedChat: () => currentChat,
      },
      actions: {
        mergeConversationMessageWindow,
      },
    });

    wrapper = shallowMount(ConversationSearchPanel, {
      attachTo: document.body,
      global: {
        plugins: [store],
        mocks: {
          $t: key => translations[key] || key,
        },
        directives: {
          dompurifyHtml: {
            beforeMount(el, binding) {
              el.innerHTML = binding.value;
            },
            updated(el, binding) {
              el.innerHTML = binding.value;
            },
          },
        },
        stubs: {
          FluentIcon: true,
          Spinner: true,
          NextButton: {
            name: 'NextButton',
            props: ['label'],
            template: '<button type="button">{{ label }}</button>',
          },
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

  it('focuses search input on mount', async () => {
    createWrapper();
    await nextTick();

    expect(document.activeElement).toBe(
      wrapper.find('[data-testid="conversation-search-input"]').element
    );
  });

  it('renders search input with icon and text spacing', async () => {
    createWrapper();
    wrapper.vm.conversationSearchQuery = 'billing';
    await nextTick();

    const input = wrapper.find('[data-testid="conversation-search-input"]');
    const searchIcon = wrapper.find('fluent-icon-stub[icon="search"]');
    const clearButton = wrapper.find(
      '[data-testid="conversation-search-clear"]'
    );

    expect(input.classes()).toEqual(
      expect.arrayContaining([
        'reset-base',
        'pl-12',
        'pr-12',
        'mb-0',
        'rtl:pr-10',
        'rtl:pl-12',
      ])
    );
    expect(input.classes()).not.toContain('pl-10');
    expect(searchIcon.exists()).toBe(true);
    expect(clearButton.classes()).toEqual(
      expect.arrayContaining(['right-1', 'top-1/2', '-translate-y-1/2'])
    );
    expect(input.attributes('placeholder')).toBe('Search in conversation');
    expect(input.attributes('aria-label')).toBe('Search in conversation');
  });

  it('does not render the start searching copy or result counter', async () => {
    createWrapper();
    wrapper.vm.conversationSearchMeta = { total_count: 2 };
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    expect(wrapper.text()).not.toContain(
      ['Search', 'this', 'conversation'].join(' ')
    );
    expect(
      wrapper.find('[data-testid="conversation-search-counter"]').exists()
    ).toBe(false);
  });

  it('defines conversation search i18n keys in en and pt_BR', () => {
    const requiredKeys = [
      'PANEL_TITLE',
      'SEARCH_IN_CONVERSATION',
      'CLOSE_SEARCH',
      'CLEAR_SEARCH',
      'NO_RESULTS',
      'FAILED_TO_SEARCH_MESSAGES',
      'MESSAGE_UNAVAILABLE',
      'FAILED_TO_LOAD_MESSAGE',
      'LOAD_MORE',
      'HAS_ATTACHMENT',
      'AGENT',
      'CONTACT',
    ];

    requiredKeys.forEach(key => {
      expect(enConversationMessages.CONVERSATION.SEARCH[key]).toBeTruthy();
      expect(ptBRConversationMessages.CONVERSATION.SEARCH[key]).toBeTruthy();
    });
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

  it('calls search endpoint for a valid query and renders results', async () => {
    MessageApi.searchMessages.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            content: 'Billing question',
            created_at: 1621145476,
            sender: { name: 'Ada' },
          },
        ],
        meta: { total_count: 1 },
      },
    });
    createWrapper();

    await wrapper.vm.searchConversationMessages(' billing ');
    await nextTick();

    expect(MessageApi.searchMessages).toHaveBeenCalledWith(1, {
      q: 'billing',
      signal: expect.any(AbortSignal),
    });
    expect(
      wrapper.find('[data-testid="conversation-search-results"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="conversation-search-result"]').text()
    ).toContain('Ada');
    expect(wrapper.find('.conversation-search-panel-highlight').text()).toBe(
      'Billing'
    );
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

    expect(
      wrapper.find('[data-testid="conversation-search-loading"]').exists()
    ).toBe(true);

    resolveSearch({ data: { payload: [], meta: {} } });
    await searchPromise;

    expect(wrapper.vm.isSearchingConversationMessages).toBe(false);
  });

  it('renders empty state', async () => {
    MessageApi.searchMessages.mockResolvedValue({
      data: { payload: [], meta: {} },
    });
    createWrapper();

    await wrapper.vm.searchConversationMessages('missing');
    await nextTick();

    expect(
      wrapper.find('[data-testid="conversation-search-no-results"]').text()
    ).toBe('No results');
  });

  it('renders search errors', async () => {
    MessageApi.searchMessages.mockRejectedValue(new Error('Search failed'));
    createWrapper();

    await wrapper.vm.searchConversationMessages('billing');
    await nextTick();

    expect(
      wrapper.find('[data-testid="conversation-search-error"]').text()
    ).toBe('Failed to search messages');
  });

  it('appends load more results and preserves query', async () => {
    MessageApi.searchMessages.mockResolvedValue({
      data: {
        payload: [{ id: 1, content: 'Billing follow up' }],
        meta: { total_count: 2, limit: 20, has_more: false },
      },
    });
    createWrapper();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.conversationSearchResults = [{ id: 2, content: 'Billing' }];
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
      { id: 2, content: 'Billing' },
      { id: 1, content: 'Billing follow up' },
    ]);
  });

  it('aborts stale search requests and ignores stale responses', async () => {
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
    await nextTick();
    const firstSignal = MessageApi.searchMessages.mock.calls[0][1].signal;

    await wrapper.vm.searchConversationMessages('refund');

    resolveFirstSearch({
      data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
    });
    await firstSearchPromise;

    expect(firstSignal.aborted).toBe(true);
    expect(wrapper.vm.conversationSearchResults).toEqual([{ id: 2 }]);
    expect(wrapper.vm.conversationSearchQuery).toBe('refund');
  });

  it('triggers debounced backend search from input', async () => {
    vi.useFakeTimers();
    MessageApi.searchMessages.mockResolvedValue({
      data: { payload: [{ id: 1 }], meta: { total_count: 1 } },
    });
    createWrapper();

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

  it('selects next and previous results from Enter shortcuts', async () => {
    currentChat.messages = [{ id: 1 }, { id: 2 }];
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }, { id: 1 }];
    wrapper.vm.activeConversationSearchResultIndex = 0;
    await nextTick();

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Enter' });

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(1);

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Enter', shiftKey: true });

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(0);
  });

  it('does not request a message window for a loaded result', async () => {
    currentChat.messages = [{ id: 2 }];
    createWrapper();
    wrapper.vm.conversationSearchResults = [{ id: 2 }];

    await wrapper.vm.selectConversationSearchResult(0);

    expect(wrapper.vm.activeConversationSearchResultIndex).toBe(0);
    expect(mergeConversationMessageWindow).not.toHaveBeenCalled();
    expect(wrapper.emitted('searchStateChange').at(-1)[0]).toEqual({
      query: '',
      activeResultId: 2,
    });
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

  it('closes with X and Escape', async () => {
    createWrapper();

    await wrapper
      .find('[data-testid="conversation-search-close"]')
      .trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);

    await wrapper
      .find('[data-testid="conversation-search-input"]')
      .trigger('keydown', { key: 'Escape' });

    expect(wrapper.emitted('close')).toHaveLength(2);
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
    wrapper.vm.closePanel();

    expect(signal.aborted).toBe(true);
  });
});
