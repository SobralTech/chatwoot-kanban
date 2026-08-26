import { flushPromises, shallowMount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';

import KanbanBoardCreate from '../KanbanBoardCreate.vue';
import KanbanBoardTemplatePicker from '../KanbanBoardTemplatePicker.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const mockPush = vi.fn();
const mockReplace = vi.fn();
const mockT = vi.hoisted(() => vi.fn(key => key));

const mockRoute = reactive({
  name: 'kanban_board_create_form',
  params: { accountId: '1' },
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: mockT }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    create: vi.fn(),
    templates: vi.fn(),
  },
}));

const templatesResponse = () => [
  {
    key: 'sales',
    name: 'Sales',
    description: 'From first contact to closing the deal',
    stages: ['New contact', 'Qualification'],
    won_stage_name: 'Won',
    lost_stage_name: 'Lost',
    lost_reasons_count: 5,
    custom_fields_count: 0,
  },
  {
    key: 'blank',
    name: 'Blank',
    description: 'Just the essentials',
    stages: ['Inbox'],
    won_stage_name: 'Won',
    lost_stage_name: 'Lost',
    lost_reasons_count: 0,
    custom_fields_count: 0,
  },
];

const createTestStore = (boards = []) =>
  createStore({
    modules: {
      kanbanBoards: {
        namespaced: true,
        state: { records: boards },
        getters: { kanbanBoards: state => state.records },
        actions: {
          fetchBoards: vi.fn(),
          refreshBoards: vi.fn(),
        },
      },
    },
  });

const mountCreate = async (boards = []) => {
  KanbanBoardsAPI.templates.mockResolvedValue({ data: templatesResponse() });
  KanbanBoardsAPI.create.mockResolvedValue({ data: { id: 22 } });

  const wrapper = shallowMount(KanbanBoardCreate, {
    global: {
      plugins: [createTestStore(boards)],
      stubs: {
        Button: {
          name: 'Button',
          props: ['label', 'disabled', 'isLoading'],
          template:
            '<button v-bind="$attrs" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        WootModal: {
          name: 'WootModal',
          props: ['show'],
          template: '<div v-if="show"><slot /></div>',
        },
      },
    },
  });

  await flushPromises();
  return wrapper;
};

const selectTemplate = async (wrapper, key) => {
  wrapper.findComponent(KanbanBoardTemplatePicker).vm.$emit('select', key);
  await flushPromises();
};

describe('KanbanBoardCreate', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('creates an active funnel named after the template and opens the board', async () => {
    const wrapper = await mountCreate();

    await selectTemplate(wrapper, 'sales');

    expect(KanbanBoardsAPI.create).toHaveBeenCalledWith({
      template_key: 'sales',
      kanban_board: { name: 'Sales', position: 0 },
    });
    expect(mockReplace).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 22 },
    });
    expect(
      wrapper.find('[data-testid="kanban-board-create-name-modal"]').exists()
    ).toBe(false);
  });

  it('asks for a name before creating a blank funnel', async () => {
    const wrapper = await mountCreate();

    await selectTemplate(wrapper, 'blank');

    expect(KanbanBoardsAPI.create).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-board-create-name-modal"]').exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-board-create-name-input"]')
      .setValue('  My funnel  ');
    await wrapper
      .find('[data-testid="kanban-board-create-name-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.create).toHaveBeenCalledWith({
      template_key: 'blank',
      kanban_board: { name: 'My funnel', position: 0 },
    });
    expect(mockReplace).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 22 },
    });
  });

  it('prefills the name dialog when the template name is already taken', async () => {
    const wrapper = await mountCreate([{ id: 1, name: 'sales ' }]);

    await selectTemplate(wrapper, 'sales');

    expect(KanbanBoardsAPI.create).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-board-create-name-input"]').element
        .value
    ).toBe('Sales');
    expect(
      wrapper.find('[data-testid="kanban-board-create-name-taken"]').exists()
    ).toBe(true);
    expect(
      wrapper
        .find('[data-testid="kanban-board-create-name-confirm"]')
        .attributes('disabled')
    ).toBeDefined();

    await wrapper
      .find('[data-testid="kanban-board-create-name-input"]')
      .setValue('Sales 2');
    await wrapper
      .find('[data-testid="kanban-board-create-name-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.create).toHaveBeenCalledWith({
      template_key: 'sales',
      kanban_board: { name: 'Sales 2', position: 1 },
    });
  });
});
