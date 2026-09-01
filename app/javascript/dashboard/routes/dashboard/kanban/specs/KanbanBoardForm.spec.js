import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createStore } from 'vuex';

import KanbanBoardForm from '../KanbanBoardForm.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const mockPush = vi.fn();
const mockT = vi.hoisted(() => vi.fn(key => key));
let routeLeaveGuard;

const mockRoute = reactive({
  params: { accountId: '1', boardId: '10' },
});

const mockReplace = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: mockT }),
}));

vi.mock('vue-router', () => ({
  onBeforeRouteLeave: guard => {
    routeLeaveGuard = guard;
  },
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush, replace: mockReplace }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    delete: vi.fn(),
    deleteStage: vi.fn(),
    getSettings: vi.fn(),
    showBoard: vi.fn(),
    update: vi.fn(),
    updateSettings: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    reorderStage: vi.fn(),
    importExistingConversations: vi.fn(),
  },
}));

const settingsResponse = (overrides = {}) => ({
  id: 10,
  name: 'Sales funnel',
  description: 'Original description',
  active: true,
  auto_create_cards_from_conversations: false,
  visibility_mode: 'selected_agents',
  visible_user_ids: [1, 2],
  inbox_scope_mode: 'all_inboxes',
  allowed_inbox_ids: [],
  won_stage_id: 100,
  lost_stage_id: 200,
  lost_reason_required: false,
  won_recurrence_enabled: false,
  won_recurrence_window_minutes: null,
  lost_recurrence_enabled: false,
  lost_recurrence_window_minutes: null,
  ...overrides,
});

const boardResponse = (overrides = {}) => ({
  id: 10,
  stages: [
    { id: 100, name: 'Qualified', position: 1, cards: [] },
    { id: 200, name: 'Won', position: 2, cards: [] },
  ],
  ...overrides,
});

const createTestStore = () =>
  createStore({
    getters: {
      getCurrentRole: () => 'administrator',
    },
    modules: {
      inboxes: {
        namespaced: true,
        state: { records: [{ id: 1, name: 'Support' }] },
        getters: { getAllInboxes: state => state.records },
        actions: { get: vi.fn() },
      },
      agents: {
        namespaced: true,
        actions: { get: vi.fn() },
      },
      kanbanBoards: {
        namespaced: true,
        state: { records: [] },
        getters: { kanbanBoards: state => state.records },
        actions: {
          fetchBoards: vi.fn(),
          refreshBoards: vi.fn(),
        },
      },
    },
  });

const mountForm = async ({ settings, board } = {}) => {
  KanbanBoardsAPI.getSettings.mockResolvedValue({
    data: settings || settingsResponse(),
  });
  KanbanBoardsAPI.showBoard.mockResolvedValue({
    data: board || boardResponse(),
  });
  KanbanBoardsAPI.updateSettings.mockResolvedValue({
    data: settings || settingsResponse(),
  });
  KanbanBoardsAPI.update.mockResolvedValue({ data: { active: true } });
  KanbanBoardsAPI.delete.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.deleteStage.mockResolvedValue({ data: {} });

  const wrapper = shallowMount(KanbanBoardForm, {
    global: {
      plugins: [createTestStore()],
      stubs: {
        Button: {
          name: 'Button',
          props: ['label', 'disabled', 'isLoading'],
          template:
            '<button v-bind="$attrs" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
        Switch: {
          name: 'Switch',
          template: '<button @click="$emit(\'change\')" />',
        },
        TabBar: {
          name: 'TabBar',
          props: ['tabs'],
          template: '<div />',
        },
        AgentTagInput: {
          name: 'AgentTagInput',
          props: ['modelValue'],
          template: '<div />',
        },
        TagMultiSelectComboBox: {
          name: 'TagMultiSelectComboBox',
          props: ['modelValue'],
          template: '<div />',
        },
        Draggable: {
          name: 'Draggable',
          props: {
            modelValue: {
              type: Array,
              default: () => [],
            },
          },
          template:
            '<div><slot /><slot v-for="element in modelValue" name="item" :element="element" /></div>',
        },
        ColorPicker: {
          name: 'ColorPicker',
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<button v-bind="$attrs" @click="$emit(\'update:modelValue\', \'#FF6B6B\')" />',
        },
        KanbanCustomFieldsTab: true,
        KanbanReasonsTab: true,
        WootModal: {
          name: 'WootModal',
          props: ['show'],
          template: '<div v-if="show"><slot /></div>',
        },
        WootDeleteModal: {
          name: 'WootDeleteModal',
          props: ['show', 'onConfirm'],
          template:
            '<button v-if="show" data-testid="kanban-board-form-delete-modal-confirm" @click="onConfirm" />',
        },
      },
    },
  });

  await flushPromises();
  await nextTick();
  return wrapper;
};

const invokeRouteLeave = next =>
  routeLeaveGuard(
    { name: 'kanban_boards', params: { accountId: '1' } },
    {},
    next
  );

describe('KanbanBoardForm', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockT.mockImplementation(key => key);
    routeLeaveGuard = undefined;
    mockRoute.params.accountId = '1';
    mockRoute.params.boardId = '10';
  });

  it('shows save actions only for changes and clears them when the name is restored', async () => {
    const wrapper = await mountForm();
    const nameInput = wrapper.find('[data-testid="kanban-board-form-name"]');

    expect(
      wrapper.find('[data-testid="kanban-board-form-save"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-board-form-discard"]').exists()
    ).toBe(false);

    await nameInput.setValue('Updated funnel');

    expect(
      wrapper.find('[data-testid="kanban-board-form-save"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-board-form-discard"]').exists()
    ).toBe(true);

    await nameInput.setValue('Sales funnel');

    expect(
      wrapper.find('[data-testid="kanban-board-form-save"]').exists()
    ).toBe(false);
  });

  it('navigates back to the funnel from an existing board form', async () => {
    const wrapper = await mountForm();

    await wrapper
      .find('[data-testid="kanban-board-form-back"]')
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 10 },
    });
  });

  it('does not mark a reordered set of visible agents as dirty', async () => {
    const wrapper = await mountForm();

    await wrapper
      .findComponent({ name: 'AgentTagInput' })
      .vm.$emit('update:modelValue', [2, 1]);

    expect(
      wrapper.find('[data-testid="kanban-board-form-save"]').exists()
    ).toBe(false);
  });

  it('only persists settings after clicking Save', async () => {
    const wrapper = await mountForm();

    await wrapper
      .find('[data-testid="kanban-board-form-name"]')
      .setValue('Updated funnel');
    await wrapper
      .find('[data-testid="kanban-board-form-name"]')
      .trigger('blur');

    expect(KanbanBoardsAPI.updateSettings).not.toHaveBeenCalled();

    await wrapper
      .find('[data-testid="kanban-board-form-save"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateSettings).toHaveBeenCalledTimes(1);
  });

  const openCreateStagePanel = async wrapper => {
    await wrapper
      .find('[data-testid="kanban-board-form-create-stage-toggle"]')
      .trigger('click');

    return wrapper.findComponent({ name: 'KanbanStageEditPanel' });
  };

  it('persists the name and colour reported by the create stage panel', async () => {
    const wrapper = await mountForm();

    const panel = await openCreateStagePanel(wrapper);
    await panel.vm.$emit('update:name', 'Negotiation');
    await panel.vm.$emit('update:color', '#FF6B6B');
    await panel.vm.$emit('save');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Negotiation',
        description: '',
        color: '#FF6B6B',
        position: 1,
        sla_hours: null,
      },
    });
  });

  it('sends the stage time limit when the create panel reports one', async () => {
    const wrapper = await mountForm();

    const panel = await openCreateStagePanel(wrapper);
    await panel.vm.$emit('update:name', 'Negotiation');
    await panel.vm.$emit('update:slaHours', '48');
    await panel.vm.$emit('save');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(
      10,
      expect.objectContaining({
        stage: expect.objectContaining({ sla_hours: 48 }),
      })
    );
  });

  it('keeps the current route when continuing to edit unsaved changes', async () => {
    const wrapper = await mountForm();
    const next = vi.fn();

    await wrapper
      .find('[data-testid="kanban-board-form-name"]')
      .setValue('Updated funnel');
    invokeRouteLeave(next);
    await nextTick();

    expect(
      wrapper
        .find('[data-testid="kanban-board-form-unsaved-changes-modal"]')
        .exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-board-form-unsaved-changes-modal"] button')
      .trigger('click');

    expect(next).toHaveBeenCalledWith(false);
  });

  it('keeps dirty changes and the route when save and exit fails', async () => {
    const wrapper = await mountForm();
    const next = vi.fn();
    KanbanBoardsAPI.updateSettings.mockRejectedValueOnce(new Error('failed'));

    await wrapper
      .find('[data-testid="kanban-board-form-name"]')
      .setValue('Updated funnel');
    invokeRouteLeave(next);
    await nextTick();

    await wrapper
      .find('[data-testid="kanban-board-form-save-and-exit"]')
      .trigger('click');
    await flushPromises();

    expect(next).toHaveBeenCalledWith(false);
    expect(
      wrapper.find('[data-testid="kanban-board-form-save"]').exists()
    ).toBe(true);
  });

  it('keeps terminal stages out of the removal controls', async () => {
    const wrapper = await mountForm();

    expect(
      wrapper.findAll('[data-testid="kanban-board-form-remove-stage"]')
    ).toHaveLength(0);
    expect(
      wrapper.find('[data-testid="kanban-board-form-won-stage"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-board-form-lost-stage"]').exists()
    ).toBe(false);
    expect(wrapper.text()).toContain(
      'KANBAN.BOARD_EDIT.STAGES_TAB.TERMINAL_STAGES_TITLE'
    );
    expect(wrapper.findAll('.stage-drag-handle')).toHaveLength(0);

    await wrapper
      .findAll('[data-testid="kanban-board-form-edit-stage"]')[0]
      .trigger('click');
    expect(
      wrapper
        .find('[data-testid="kanban-board-form-edit-stage-color"]')
        .exists()
    ).toBe(false);
  });

  it('reorders regular stages with positions before terminals', async () => {
    const wrapper = await mountForm({
      board: boardResponse({
        stages: [
          { id: 50, name: 'Inbox', position: 1, cards: [] },
          { id: 100, name: 'Won', position: 2, cards: [] },
          { id: 200, name: 'Lost', position: 3, cards: [] },
        ],
      }),
    });

    await wrapper.vm.onStageDragEnd({
      item: { dataset: { stageId: '50' } },
      oldIndex: 0,
      newIndex: 1,
    });

    expect(KanbanBoardsAPI.reorderStage).toHaveBeenCalledWith(10, 50, {
      position: 2,
    });
  });

  it('enables Save without terminal stages', async () => {
    const wrapper = await mountForm({
      settings: settingsResponse({ won_stage_id: null, lost_stage_id: null }),
    });

    await wrapper
      .find('[data-testid="kanban-board-form-name"]')
      .setValue('Updated funnel');

    expect(
      wrapper
        .find('[data-testid="kanban-board-form-save"]')
        .attributes('disabled')
    ).toBeUndefined();
  });
});
