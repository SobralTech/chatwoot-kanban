import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';

import ConversationBox from '../ConversationBox.vue';

describe('ConversationBox', () => {
  let currentChat;
  let store;
  let wrapper;
  let updateUISettings;
  let uiSettings;

  const createWrapper = () => {
    uiSettings = {
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    };
    updateUISettings = vi.fn();
    store = createStore({
      state: {
        uiSettings,
      },
      getters: {
        getSelectedChat: () => currentChat,
        getUISettings: state => state.uiSettings,
      },
      actions: {
        'conversationLabels/get': vi.fn(),
        'dashboardApps/get': vi.fn(),
        'inboxAssignableAgents/fetch': vi.fn(),
        updateUISettings,
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
        },
      },
    });

    return wrapper;
  };

  beforeEach(() => {
    currentChat = { id: 1, inbox_id: 2, messages: [] };
  });

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('renders the conversation messages view when a conversation exists', () => {
    createWrapper();

    expect(wrapper.findComponent({ name: 'MessagesView' }).exists()).toBe(true);
  });

  it('opens search panel with Ctrl+F when a conversation exists', async () => {
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
    expect(wrapper.emitted('conversationSearchOpen')).toHaveLength(1);
  });

  it('opens search panel with Cmd+F when a conversation exists', async () => {
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

  it('opens and toggles search from the conversation header action', async () => {
    createWrapper();
    const header = wrapper.findComponent({ name: 'ConversationHeader' });

    header.vm.$emit('openConversationSearch');
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(true);

    header.vm.$emit('openConversationSearch');
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
  });

  it('does not render the search panel inside the old conversation area', async () => {
    createWrapper();

    wrapper.vm.openConversationSearch();
    await nextTick();

    expect(
      wrapper.find('[data-testid="conversation-search-bar"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="conversation-search-panel"]').exists()
    ).toBe(false);
    expect(
      wrapper
        .find('[data-testid="conversation-main-region"]')
        .find('[data-testid="conversation-search-panel"]')
        .exists()
    ).toBe(false);
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

  it('closes contact and copilot side panels when opening search', async () => {
    createWrapper();

    wrapper.vm.openConversationSearch();
    await nextTick();

    expect(updateUISettings).toHaveBeenCalledWith(expect.any(Object), {
      uiSettings: {
        is_contact_sidebar_open: false,
        is_copilot_panel_open: false,
      },
    });
  });

  it('closes search when contact details are opened from the header', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    await nextTick();

    wrapper
      .findComponent({ name: 'ConversationHeader' })
      .vm.$emit('toggleContactDetails', true);
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
  });

  it('closes search when the contact panel is opened from another side panel control', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    await nextTick();

    store.state.uiSettings.is_contact_sidebar_open = true;
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
  });

  it('keeps search open when contact details are closed from the header', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    await nextTick();

    wrapper
      .findComponent({ name: 'ConversationHeader' })
      .vm.$emit('toggleContactDetails', false);
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(true);
  });

  it('passes search state from the panel to messages view', async () => {
    createWrapper();
    wrapper.vm.openConversationSearch();
    await nextTick();

    wrapper.vm.onConversationSearchStateChange({
      query: 'billing',
      activeResultId: 2,
    });
    await nextTick();

    const messagesView = wrapper.findComponent({ name: 'MessagesView' });

    expect(messagesView.props('conversationSearchQuery')).toBe('billing');
    expect(messagesView.props('activeConversationSearchResultId')).toBe(2);
  });

  it('clears search highlight state when the panel closes', async () => {
    createWrapper();
    wrapper.vm.conversationSearchQuery = 'billing';
    wrapper.vm.activeConversationSearchResultId = 2;
    wrapper.vm.openConversationSearch();
    await nextTick();

    wrapper.vm.closeConversationSearch();
    await nextTick();

    expect(wrapper.vm.isConversationSearchOpen).toBe(false);
    expect(wrapper.vm.conversationSearchQuery).toBe('');
    expect(wrapper.vm.activeConversationSearchResultId).toBeNull();
    expect(wrapper.emitted('conversationSearchClose')).toHaveLength(1);
  });
});
