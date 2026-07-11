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

const mountView = ({
  currentChat = { id: 1, inbox_id: 2 },
  routeName = 'inbox_conversation',
  conversationId = 1,
} = {}) => {
  const store = createStoreMock(currentChat);
  const router = { replace: vi.fn(), push: vi.fn() };

  const wrapper = shallowMount(ConversationView, {
    props: {
      conversationId,
      inboxId: 2,
    },
    global: {
      plugins: [store],
      mocks: {
        $route: { query: {}, name: routeName },
        $router: router,
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

  return { wrapper, router, currentChat };
};

describe('ConversationView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.uiSettings.conversation_display_type = 'expanded';
    mocks.uiSettings.is_contact_sidebar_open = true;
    mocks.uiSettings.is_copilot_panel_open = false;
  });

  it('renders search panel beside conversation box and replaces profile sidebar', async () => {
    const { wrapper } = mountView();

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
    const { wrapper } = mountView();

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

  describe('syncRouteWithArchivedState', () => {
    it('redirects to the archived route when the open conversation gets archived elsewhere', () => {
      // Covers both a live archive from another agent and opening an
      // already-archived conversation through a generic/old URL: both
      // surface as currentChat.archived_at becoming truthy while we're not
      // already on the archived route.
      const { wrapper, router } = mountView({
        currentChat: { id: 1, inbox_id: 2 },
        routeName: 'inbox_conversation',
        conversationId: 1,
      });

      wrapper.vm.syncRouteWithArchivedState(1752230400);

      expect(router.replace).toHaveBeenCalledWith({
        name: 'conversation_through_archived',
        params: { conversationId: 1 },
      });
    });

    it('redirects back to the archived list when the open conversation gets unarchived elsewhere', () => {
      const { wrapper, router } = mountView({
        currentChat: { id: 1, inbox_id: 2 },
        routeName: 'conversation_through_archived',
        conversationId: 1,
      });

      wrapper.vm.syncRouteWithArchivedState(null);

      expect(router.replace).toHaveBeenCalledWith(
        '/app/accounts/1/archived/conversations'
      );
    });

    it('does not redirect when already on the matching route', () => {
      const { wrapper, router } = mountView({
        currentChat: { id: 1, inbox_id: 2 },
        routeName: 'conversation_through_archived',
        conversationId: 1,
      });

      wrapper.vm.syncRouteWithArchivedState(1752230400);

      expect(router.replace).not.toHaveBeenCalled();
    });

    it('ignores stale updates for a conversation other than the one on-screen', () => {
      const { wrapper, router } = mountView({
        currentChat: { id: 99, inbox_id: 2 },
        routeName: 'inbox_conversation',
        conversationId: 1,
      });

      wrapper.vm.syncRouteWithArchivedState(1752230400);

      expect(router.replace).not.toHaveBeenCalled();
    });
  });
});
