import { mount, flushPromises } from '@vue/test-utils';
import { computed, h, nextTick, ref } from 'vue';
import { createStore } from 'vuex';
import Sidebar from '../Sidebar.vue';

const mockAccountId = ref(1);
const mockWindowWidth = ref(1024);

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      ({
        'SIDEBAR.KANBAN': 'Kanban',
        'SIDEBAR.KANBAN_OVERVIEW': 'Overview',
      })[key] || key,
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params, query) => ({
      name,
      params: { accountId: mockAccountId.value, ...(params || {}) },
      query: { ...(query || {}) },
    }),
    isOnChatwootCloud: computed(() => false),
  }),
}));

vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => 'mod+k',
}));

vi.mock('../useSidebarKeyboardShortcuts', () => ({
  useSidebarKeyboardShortcuts: vi.fn(),
}));

vi.mock('../provider', () => ({
  provideSidebarContext: vi.fn(),
  useSidebarResize: () => ({
    sidebarWidth: ref(200),
    isCollapsed: ref(false),
    setSidebarWidth: vi.fn(),
    saveWidth: vi.fn(),
    snapToCollapsed: vi.fn(),
    snapToExpanded: vi.fn(),
    COLLAPSED_THRESHOLD: 160,
  }),
}));

vi.mock('@vueuse/core', () => ({
  useWindowSize: () => ({ width: mockWindowWidth }),
  useEventListener: vi.fn(),
}));

const SidebarGroupStub = {
  name: 'SidebarGroup',
  props: ['name', 'label', 'icon', 'to', 'activeOn', 'children'],
  setup(props) {
    return () =>
      h('li', { 'data-testid': `sidebar-group-${props.name}` }, [
        h('span', props.label),
        props.children?.map(child =>
          h(
            'a',
            {
              'data-testid': `sidebar-child-${child.name}`,
              'data-route-name': child.to?.name,
              'data-account-id': child.to?.params?.accountId,
              'data-board-id': child.to?.params?.boardId,
              'data-active-on': child.activeOn?.join(','),
            },
            child.label
          )
        ),
      ]);
  },
};

const buildStore = ({ accountId = 1, boards = [] } = {}) => {
  const state = {
    currentAccountId: accountId,
    kanbanBoards: boards,
    kanbanBoardsLoading: false,
  };

  const actions = {
    labelsGet: vi.fn(),
    inboxesGet: vi.fn(),
    notificationsUnreadCount: vi.fn(),
    teamsGet: vi.fn(),
    attributesGet: vi.fn(),
    customViewsGet: vi.fn(),
    conversationUnreadCountsGet: vi.fn(),
    conversationUnreadCountsClear: vi.fn(),
    kanbanFetchBoards: vi.fn(),
    kanbanResetBoards: vi.fn(),
  };

  const store = createStore({
    state,
    getters: {
      getCurrentAccountId: localState => localState.currentAccountId,
      'globalConfig/isACustomBrandedInstance': () => false,
      'accounts/isRTL': () => false,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'inboxes/getInboxes': () => [],
      'labels/getLabelsOnSidebar': () => [],
      'conversationUnreadCounts/getInboxUnreadCount': () => () => 0,
      'conversationUnreadCounts/getLabelUnreadCount': () => () => 0,
      'conversationUnreadCounts/getTeamUnreadCount': () => () => 0,
      'teams/getMyTeams': () => [],
      'customViews/getContactCustomViews': () => [],
      'customViews/getConversationCustomViews': () => [],
      'kanbanBoards/kanbanBoards': localState => localState.kanbanBoards,
      'kanbanBoards/kanbanBoardsLoading': localState =>
        localState.kanbanBoardsLoading,
    },
    mutations: {
      setCurrentAccountId(localState, newAccountId) {
        localState.currentAccountId = newAccountId;
      },
    },
    actions: {
      'labels/get': actions.labelsGet,
      'inboxes/get': actions.inboxesGet,
      'notifications/unReadCount': actions.notificationsUnreadCount,
      'teams/get': actions.teamsGet,
      'attributes/get': actions.attributesGet,
      'customViews/get': actions.customViewsGet,
      'conversationUnreadCounts/get': actions.conversationUnreadCountsGet,
      'conversationUnreadCounts/clear': actions.conversationUnreadCountsClear,
      'kanbanBoards/fetchBoards': actions.kanbanFetchBoards,
      'kanbanBoards/resetBoards': actions.kanbanResetBoards,
    },
  });

  return { store, state, actions };
};

const mountSidebar = options => {
  const { store, state, actions } = buildStore(options);
  const wrapper = mount(Sidebar, {
    global: {
      plugins: [store],
      directives: {
        OnClickOutside: vi.fn(),
      },
      stubs: {
        SidebarGroup: SidebarGroupStub,
        RouterLink: {
          props: ['to'],
          template: '<a><slot /></a>',
        },
        Button: true,
        SidebarProfileMenu: true,
        SidebarChangelogCard: true,
        SidebarChangelogButton: true,
        ChannelLeaf: true,
        ChannelIcon: true,
        SidebarAccountSwitcher: true,
        Logo: true,
        ComposeConversation: {
          template: '<div><slot name="trigger" :is-open="false" /></div>',
        },
      },
    },
  });

  return { wrapper, store, state, actions };
};

const findKanbanGroup = wrapper =>
  wrapper
    .findAllComponents(SidebarGroupStub)
    .find(group => group.props('name') === 'Kanban');

describe('Sidebar', () => {
  beforeEach(() => {
    mockAccountId.value = 1;
    mockWindowWidth.value = 1024;
  });

  it('shows overview in the kanban submenu', () => {
    const { wrapper } = mountSidebar();
    const kanbanGroup = findKanbanGroup(wrapper);

    expect(kanbanGroup.props('children')[0]).toMatchObject({
      name: 'Kanban Overview',
      label: 'Overview',
      activeOn: ['kanban_boards'],
      to: {
        name: 'kanban_boards',
        params: { accountId: 1 },
      },
    });
  });

  it('shows kanban boards from the shared store in backend order', () => {
    const { wrapper } = mountSidebar({
      boards: [
        { id: 2, name: 'Renewals' },
        { id: 1, name: 'Sales' },
      ],
    });
    const children = findKanbanGroup(wrapper).props('children');

    expect(children.map(child => child.label)).toEqual([
      'Overview',
      'Renewals',
      'Sales',
    ]);
  });

  it('points board links to the board show route', () => {
    const { wrapper } = mountSidebar({
      boards: [{ id: 7, name: 'Sales' }],
    });
    const boardChild = findKanbanGroup(wrapper).props('children')[1];

    expect(boardChild).toMatchObject({
      activeOn: ['kanban_board_show', 'kanban_board_settings'],
      to: {
        name: 'kanban_board_show',
        params: { accountId: 1, boardId: 7 },
      },
    });
  });

  it('keeps active route metadata for overview and board items', () => {
    const { wrapper } = mountSidebar({
      boards: [{ id: 7, name: 'Sales' }],
    });
    const [overview, board] = findKanbanGroup(wrapper).props('children');

    expect(overview.activeOn).toEqual(['kanban_boards']);
    expect(board.activeOn).toEqual([
      'kanban_board_show',
      'kanban_board_settings',
    ]);
    expect(board.to.params.boardId).toBe(7);
  });

  it('does not break the kanban submenu when there are no boards', () => {
    const { wrapper } = mountSidebar();
    const kanbanChildren = findKanbanGroup(wrapper).props('children');

    expect(kanbanChildren).toHaveLength(1);
    expect(
      wrapper.find('[data-testid="sidebar-child-Kanban Overview"]').text()
    ).toBe('Overview');
  });

  it('refreshes kanban boards when the account changes', async () => {
    const { store, actions } = mountSidebar({
      boards: [{ id: 1, name: 'Sales' }],
    });

    store.commit('setCurrentAccountId', 2);
    mockAccountId.value = 2;
    await nextTick();
    await flushPromises();

    expect(actions.kanbanResetBoards).toHaveBeenCalledTimes(1);
    expect(actions.kanbanFetchBoards).toHaveBeenCalledTimes(1);
  });

  it('fetches kanban boards on mount when the shared store is empty', async () => {
    const { actions } = mountSidebar();
    await flushPromises();

    expect(actions.kanbanFetchBoards).toHaveBeenCalledTimes(1);
  });

  it('keeps other sidebar groups available', () => {
    const { wrapper } = mountSidebar();
    const groupNames = wrapper
      .findAllComponents(SidebarGroupStub)
      .map(group => group.props('name'));

    expect(groupNames).toContain('Inbox');
    expect(groupNames).toContain('Conversation');
    expect(groupNames).toContain('Settings');
  });
});
