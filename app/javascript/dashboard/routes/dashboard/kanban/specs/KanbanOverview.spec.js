import { shallowMount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import KanbanOverview from '../KanbanOverview.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import kanbanBoardsModule from 'dashboard/store/modules/kanbanBoards';

const mockPush = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
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
  const wrapper = shallowMount(KanbanOverview, {
    global: {
      plugins: [store],
      stubs: {
        Button: {
          name: 'Button',
          props: ['icon', 'label', 'color', 'size'],
          template:
            '<button class="btn-stub" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
      },
    },
  });

  await flushPromises();
  await nextTick();
  return wrapper;
};

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
        { id: 1, name: 'Sales Board', description: 'Sales pipeline' },
        { id: 2, name: 'Support Board', description: '' },
      ],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).toContain('Sales Board');
    expect(wrapper.text()).toContain('Support Board');
    expect(wrapper.text()).toContain('Sales pipeline');
  });

  it('navigates to board on click', async () => {
    KanbanBoardsAPI.get.mockResolvedValue({
      data: [{ id: 5, name: 'Sales Board' }],
    });
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    const boardButton = wrapper.find('button');
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

    expect(wrapper.find('.btn-stub').exists()).toBe(true);
  });

  it('agent does not see create button', async () => {
    const wrapper = await mountOverview();
    await flushPromises();
    await nextTick();

    expect(wrapper.text()).not.toContain('KANBAN.OVERVIEW.CREATE_BOARD');
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

    // Fill form
    const input = wrapper.find('input[type="text"]');
    await input.setValue('New Board');

    // Submit form
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    await nextTick();

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 99 },
    });
  });
});
