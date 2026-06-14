import { shallowMount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import KanbanOverview from '../KanbanOverview.vue';
import KanbanCreateBoardDialog from '../KanbanCreateBoardDialog.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import kanbanBoardsModule from 'dashboard/store/modules/kanbanBoards';
import { COLOR_OPTIONS } from 'dashboard/components-next/button/constants';

const mockPush = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const translations = {
        'KANBAN.OVERVIEW.CREATE_BOARD': 'Adicionar Funil',
        'KANBAN.ACTIONS.CONFIRM_CREATE_BOARD': 'Criar funil',
        'KANBAN.ACTIONS.CANCEL_CREATE_BOARD': 'Cancelar criação do funil',
        'KANBAN.ACTIONS.CREATE_BOARD_ERROR':
          'Não foi possível criar o quadro kanban.',
      };

      if (params?.count !== undefined) return `${key} ${params.count}`;

      return translations[key] || key;
    },
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '1' },
  }),
  useRouter: () => ({
    push: mockPush,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
  },
}));

const createTestStore = (role = 'agent') =>
  createStore({
    modules: {
      kanbanBoards: { namespaced: true, ...kanbanBoardsModule },
      auth: {
        namespaced: true,
        state: { currentUser: { accounts: [{ id: 1, role }] } },
        getters: {
          getCurrentRole: () => role,
          getCurrentAccountId: () => 1,
        },
      },
      accounts: {
        namespaced: true,
        state: {},
      },
      globalConfig: {
        namespaced: true,
        state: {},
      },
    },
  });

const mountOverview = async (role = 'agent') => {
  const store = createTestStore(role);
  const dispatchSpy = vi.spyOn(store, 'dispatch');
  const wrapper = shallowMount(KanbanOverview, {
    global: {
      plugins: [store],
      stubs: {
        Avatar: {
          name: 'Avatar',
          props: ['name', 'src', 'size'],
          template:
            '<span class="avatar-stub" data-testid="overview-agent-avatar">{{ name }} {{ src }} {{ size }}</span>',
        },
        Button: {
          name: 'Button',
          props: ['icon', 'label', 'color', 'size'],
          template:
            '<button v-bind="$attrs" class="btn-stub" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
      },
    },
  });

  await flushPromises();
  await nextTick();
  wrapper.dispatchSpy = dispatchSpy;
  return wrapper;
};

const findCreateBoardDialog = wrapper =>
  wrapper.findComponent(KanbanCreateBoardDialog);

describe('KanbanOverview', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
  });

  it('renders the overview page without redirecting', async () => {
    const wrapper = await mountOverview();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.TITLE');
  });

  it('shows loading state', async () => {
    KanbanBoardsAPI.get.mockReturnValue(new Promise(() => {}));
    const wrapper = await mountOverview();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.LOADING');
  });

  it('shows error state and retry button', async () => {
    KanbanBoardsAPI.get.mockRejectedValue(new Error('API error'));
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.ERROR');
  });

  it('shows empty state for admin with create option', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.EMPTY_ADMIN');
  });

  it('shows empty state for agent', async () => {
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.EMPTY_AGENT');
  });

  it('lists visible boards', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [
        {
          id: 1,
          name: 'Sales Board',
          cards_count: 3,
          visibility_mode: 'all_agents',
          inbox_scope_mode: 'all_inboxes',
          stages_summary: [],
        },
        { id: 2, name: 'Support Board', cards_count: 0 },
      ],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('Sales Board');
    expect(wrapper.text()).toContain('Support Board');
    expect(wrapper.findAll('[data-testid="overview-board-card"]')).toHaveLength(
      2
    );
    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.OPPORTUNITIES_COUNT 3');
    expect(wrapper.text()).not.toContain('KANBAN.OVERVIEW.LOADING');
  });

  it('navigates to board on click', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [{ id: 5, name: 'Sales Board' }],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    const boardButton = wrapper.find('[data-testid="overview-board-card"]');
    await boardButton.trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 5 },
    });
  });

  it('admin sees create button', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    const createButton = wrapper.find(
      '[data-testid="overview-create-board-button"]'
    );
    expect(createButton.exists()).toBe(true);
    expect(createButton.text()).toContain('Adicionar Funil');
  });

  it('renders only one create button in the overview', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    const createButtons = wrapper.findAll(
      '[data-testid="overview-create-board-button"]'
    );

    expect(createButtons).toHaveLength(1);
    expect(
      wrapper
        .find('header [data-testid="overview-create-board-button"]')
        .exists()
    ).toBe(true);
  });

  it('admin sees create button at the top when boards exist', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [{ id: 1, name: 'Sales Board' }],
    });
    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    const header = wrapper.find('header');
    const createButton = header.find(
      '[data-testid="overview-create-board-button"]'
    );

    expect(createButton.exists()).toBe(true);
    expect(createButton.text()).toContain('Adicionar Funil');
  });

  it('agent sees create button', async () => {
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    const createButton = wrapper.find(
      '[data-testid="overview-create-board-button"]'
    );

    expect(createButton.exists()).toBe(true);
    expect(createButton.text()).toContain('Adicionar Funil');
  });

  it('uses valid Button colors in the overview actions', async () => {
    KanbanBoardsAPI.get.mockRejectedValue(new Error('API error'));
    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    const buttons = wrapper.findAllComponents({ name: 'Button' });
    buttons.forEach(button => {
      expect(COLOR_OPTIONS).toContain(button.props('color'));
    });

    const createButtons = buttons.filter(
      button => button.props('label') === 'Adicionar Funil'
    );
    createButtons.forEach(button => {
      expect(button.props('color')).toBe('blue');
    });
  });

  it('clicking create button opens the board creation modal', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [{ id: 1, name: 'Sales Board' }],
    });
    const wrapper = await mountOverview('agent');
    await flushPromises();
    await nextTick();

    await wrapper
      .find('[data-testid="overview-create-board-button"]')
      .trigger('click');
    await nextTick();

    expect(findCreateBoardDialog(wrapper).props('modelValue')).toBe(true);
  });

  it('closes the create modal from the reusable dialog', async () => {
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    await wrapper
      .find('[data-testid="overview-create-board-button"]')
      .trigger('click');
    await nextTick();

    findCreateBoardDialog(wrapper).vm.$emit('close');
    await nextTick();

    expect(findCreateBoardDialog(wrapper).props('modelValue')).toBe(false);
  });

  it('empty state does not render a second create button', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('KANBAN.OVERVIEW.EMPTY_AGENT');
    expect(
      wrapper.findAll('[data-testid="overview-create-board-button"]')
    ).toHaveLength(1);
  });

  it('renders stages summary pills', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [
        {
          id: 1,
          name: 'Sales Board',
          cards_count: 6,
          stages_summary: [
            { id: 11, name: 'Lead', color: 'blue', cards_count: 2 },
            { id: 12, name: 'Won', color: 'green', cards_count: 4 },
          ],
        },
      ],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    const stages = wrapper.findAll('[data-testid="overview-stage-pill"]');
    expect(stages).toHaveLength(2);
    expect(wrapper.text()).toContain('Lead');
    expect(wrapper.text()).toContain('Won');
    expect(wrapper.text()).toContain('2');
    expect(wrapper.text()).toContain('4');
  });

  it('renders visible agent avatars', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [
        {
          id: 1,
          name: 'Sales Board',
          visibility_mode: 'selected_agents',
          visible_users: [
            {
              id: 1,
              name: 'Alice Agent',
              avatar_url: 'https://example.com/alice.png',
            },
            { id: 2, name: 'Bob Agent', avatar_url: '' },
          ],
        },
      ],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    const avatars = wrapper.findAll('[data-testid="overview-agent-avatar"]');
    expect(avatars).toHaveLength(2);
    expect(wrapper.text()).toContain('Alice Agent');
    expect(wrapper.text()).toContain('https://example.com/alice.png');
    expect(wrapper.text()).toContain('Bob Agent');
  });

  it('renders linked inbox indicators', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [
        {
          id: 1,
          name: 'Sales Board',
          inbox_scope_mode: 'selected_inboxes',
          allowed_inboxes: [
            {
              id: 1,
              name: 'Website',
              channel_type: 'Channel::WebWidget',
            },
            {
              id: 2,
              name: 'Email',
              channel_type: 'Channel::Email',
            },
          ],
        },
      ],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.findAll('[data-testid="overview-inbox-pill"]')).toHaveLength(
      2
    );
    expect(wrapper.text()).toContain('Website');
    expect(wrapper.text()).toContain('Email');
  });

  it('creates board and navigates to it', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    KanbanBoardsAPI.create.mockResolvedValue({
      data: { id: 99, name: 'New Board' },
    });

    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    // Click create button
    const createBtn = wrapper.find('.btn-stub');
    await createBtn.trigger('click');
    await nextTick();

    findCreateBoardDialog(wrapper).vm.$emit('create', 'New Board');
    await flushPromises();
    await nextTick();

    expect(wrapper.dispatchSpy).toHaveBeenCalledWith(
      'kanbanBoards/refreshBoards'
    );
    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 99 },
    });
  });

  it('creates board from reusable dialog event and navigates to it', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    KanbanBoardsAPI.create.mockResolvedValue({
      data: { id: 100, name: 'Enter Board' },
    });

    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    await wrapper
      .find('[data-testid="overview-create-board-button"]')
      .trigger('click');
    await nextTick();
    findCreateBoardDialog(wrapper).vm.$emit('create', 'Enter Board');
    await flushPromises();
    await nextTick();

    expect(KanbanBoardsAPI.create).toHaveBeenCalledWith({
      kanban_board: {
        name: 'Enter Board',
        position: 0,
      },
    });
    expect(wrapper.dispatchSpy).toHaveBeenCalledWith(
      'kanbanBoards/refreshBoards'
    );
    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 100 },
    });
  });

  it('passes create errors to the reusable dialog', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({ data: [] });
    KanbanBoardsAPI.create.mockRejectedValue({
      response: { data: { error: 'Name is already taken' } },
    });

    const wrapper = await mountOverview('administrator');
    await flushPromises();
    await nextTick();

    await wrapper
      .find('[data-testid="overview-create-board-button"]')
      .trigger('click');
    await nextTick();
    findCreateBoardDialog(wrapper).vm.$emit('create', 'Existing Board');
    await flushPromises();
    await nextTick();

    expect(findCreateBoardDialog(wrapper).props('error')).toBe(
      'Name is already taken'
    );
  });
});
