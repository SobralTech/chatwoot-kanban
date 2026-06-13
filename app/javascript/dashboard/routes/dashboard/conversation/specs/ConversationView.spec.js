import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';

import ConversationView from '../ConversationView.vue';

const mocks = vi.hoisted(() => ({
  uiSettings: {
    conversation_display_type: 'expanded',
    is_contact_sidebar_open: true,
    is_copilot_panel_open: false,
  },
  forwardedSearchState: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: mocks.uiSettings,
    updateUISettings: vi.fn(),
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: 1,
  }),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

const createStoreMock = currentChat =>
  createStore({
    state: {
      route: {},
    },
    getters: {
      getAllConversations: () => [currentChat],
      getSelectedChat: () => currentChat,
    },
    actions: {
      clearSelectedState: vi.fn(),
      getConversation: vi.fn(),
      setActiveChat: vi.fn(),
      setActiveInbox: vi.fn(),
      'agents/get': vi.fn(),
      'portals/index': vi.fn(),
    },
  });

const mountView = () => {
  const currentChat = { id: 1, inbox_id: 2 };
  const store = createStoreMock(currentChat);

  const wrapper = shallowMount(ConversationView, {
    props: {
      conversationId: 1,
      inboxId: 2,
    },
    global: {
      plugins: [store],
      mocks: {
        $route: { query: {} },
      },
      stubs: {
        ChatList: {
          template: '<section data-testid="chat-list" />',
        },
        ConversationBox: {
          name: 'ConversationBox',
          template: `
            <section data-testid="conversation-box">
              <button
                data-testid="open-conversation-search"
                @click="$emit('conversationSearchOpen')"
              />
              <slot />
            </section>
          `,
          methods: {
            closeConversationSearch() {
              this.$emit('conversationSearchClose');
            },
            onConversationSearchStateChange(searchState) {
              mocks.forwardedSearchState(searchState);
            },
          },
        },
        ConversationSearchPanel: {
          name: 'ConversationSearchPanel',
          emits: ['close', 'searchStateChange'],
          template: `
            <aside data-testid="conversation-search-panel">
              <button data-testid="close-search-panel" @click="$emit('close')" />
              <button
                data-testid="emit-search-state"
                @click="$emit('searchStateChange', { query: 'billing', activeResultId: 2 })"
              />
            </aside>
          `,
        },
        ConversationSidebar: {
          template: '<aside data-testid="conversation-sidebar" />',
        },
        SidepanelSwitch: true,
        CmdBarConversationSnooze: true,
      },
    },
  });

  return wrapper;
};

describe('ConversationView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.uiSettings.conversation_display_type = 'expanded';
    mocks.uiSettings.is_contact_sidebar_open = true;
    mocks.uiSettings.is_copilot_panel_open = false;
  });

  it('renders search panel beside conversation box and replaces profile sidebar', async () => {
    const wrapper = mountView();

    expect(wrapper.find('[data-testid="conversation-sidebar"]').exists()).toBe(
      true
    );

    await wrapper
      .find('[data-testid="open-conversation-search"]')
      .trigger('click');
    await nextTick();

    const conversationBox = wrapper.find('[data-testid="conversation-box"]');
    const searchPanel = wrapper.find(
      '[data-testid="conversation-search-panel"]'
    );

    expect(searchPanel.exists()).toBe(true);
    expect(wrapper.find('[data-testid="conversation-sidebar"]').exists()).toBe(
      false
    );
    expect(searchPanel.element.parentElement).toBe(
      conversationBox.element.parentElement
    );
  });

  it('forwards search panel close and state events to ConversationBox', async () => {
    const wrapper = mountView();

    await wrapper
      .find('[data-testid="open-conversation-search"]')
      .trigger('click');
    await nextTick();

    await wrapper.find('[data-testid="emit-search-state"]').trigger('click');

    expect(mocks.forwardedSearchState).toHaveBeenCalledWith({
      query: 'billing',
      activeResultId: 2,
    });

    await wrapper.find('[data-testid="close-search-panel"]').trigger('click');
    await nextTick();

    expect(
      wrapper.find('[data-testid="conversation-search-panel"]').exists()
    ).toBe(false);
  });
});
