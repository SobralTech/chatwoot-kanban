import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import KanbanBoardSettings from '../KanbanBoardSettings.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import ptBRKanbanMessages from 'dashboard/i18n/locale/pt_BR/kanban.json';

const mockReplace = vi.fn();
const mockPush = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: {
      accountId: '1',
      boardId: '10',
    },
  }),
  useRouter: () => ({
    push: mockPush,
    replace: mockReplace,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    getSettings: vi.fn(),
    showBoard: vi.fn(),
    updateSettings: vi.fn(),
    delete: vi.fn(),
    createStage: vi.fn(),
    reorderStage: vi.fn(),
    importExistingConversations: vi.fn(),
  },
}));

const settingsPayload = {
  id: 10,
  name: 'Vendas',
  description: 'Pipeline comercial',
  visibility_mode: 'selected_agents',
  visible_user_ids: [1, 2],
  inbox_scope_mode: 'selected_inboxes',
  allowed_inbox_ids: [5, 6],
  auto_create_cards_from_conversations: true,
};

const boardPayload = {
  id: 10,
  stages: [
    { id: 100, name: 'Lead', color: 'blue', position: 1, cards_count: 3 },
    { id: 200, name: 'Won', color: 'green', position: 2, cards_count: 0 },
  ],
};

const createTestStore = (role = 'administrator') => {
  const dispatch = vi.fn((type, payload) => {
    if (type === 'agents/get' || type === 'inboxes/get') {
      return Promise.resolve();
    }

    if (type === 'kanbanBoards/refreshBoards') {
      return Promise.resolve(payload);
    }

    return Promise.resolve();
  });

  const store = createStore({
    getters: {
      getCurrentRole: () => role,
    },
    modules: {
      auth: {
        namespaced: true,
        getters: {
          getCurrentRole: () => role,
        },
      },
      agents: {
        namespaced: true,
        state: {
          records: [
            { id: 1, name: 'Alice' },
            { id: 2, name: 'Bob' },
          ],
        },
        getters: {
          getAgents: state => state.records,
        },
      },
      inboxes: {
        namespaced: true,
        state: {
          records: [
            { id: 5, name: 'Sales' },
            { id: 6, name: 'Support' },
          ],
        },
        getters: {
          getAllInboxes: state => state.records,
        },
      },
      kanbanBoards: {
        namespaced: true,
        actions: {
          refreshBoards: vi.fn(),
        },
      },
    },
  });

  store.dispatch = dispatch;
  return { store, dispatch };
};

const mountSettings = async ({
  role = 'administrator',
  getSettingsResponse = { data: settingsPayload },
  getSettingsError = null,
} = {}) => {
  if (getSettingsError) {
    KanbanBoardsAPI.getSettings.mockRejectedValue(getSettingsError);
  } else {
    KanbanBoardsAPI.getSettings.mockResolvedValue(getSettingsResponse);
  }
  KanbanBoardsAPI.showBoard.mockResolvedValue({ data: boardPayload });

  const { store, dispatch } = createTestStore(role);
  const wrapper = shallowMount(KanbanBoardSettings, {
    global: {
      plugins: [store],
      stubs: {
        Button: {
          props: ['label', 'isLoading'],
          template:
            '<button v-bind="$attrs" type="button" @click="$emit(\'click\')">{{ label }}</button>',
        },
        TagMultiSelectComboBox: {
          props: ['modelValue', 'options'],
          emits: ['update:modelValue'],
          template:
            '<div v-bind="$attrs" class="tag-select-stub"><button type="button" data-testid="tag-select-update" @click="$emit(\'update:modelValue\', options.map(option => option.value))" /></div>',
        },
        Draggable: {
          name: 'Draggable',
          props: ['modelValue', 'list'],
          emits: ['update:modelValue', 'end'],
          template:
            '<div><slot v-for="item in modelValue || list" name="item" :element="item" /></div>',
        },
        WootDeleteModal: {
          props: ['show', 'onConfirm'],
          template:
            '<button v-if="show" data-testid="confirm-delete" type="button" @click="onConfirm" />',
        },
        WootModal: {
          props: ['show'],
          template: '<div v-if="show"><slot /></div>',
        },
      },
    },
  });

  await flushPromises();
  await nextTick();
  return { wrapper, dispatch };
};

describe('KanbanBoardSettings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    KanbanBoardsAPI.updateSettings.mockResolvedValue({ data: settingsPayload });
    KanbanBoardsAPI.delete.mockResolvedValue({ data: {} });
    KanbanBoardsAPI.createStage.mockResolvedValue({
      data: { id: 300, name: 'Follow up', color: 'slate', position: 3 },
    });
    KanbanBoardsAPI.reorderStage.mockResolvedValue({ data: {} });
    KanbanBoardsAPI.importExistingConversations.mockResolvedValue({
      data: { status: 'accepted', enqueued: true, estimated_count: 3 },
    });
  });

  it('loads the page settings', async () => {
    const { wrapper, dispatch } = await mountSettings();

    expect(KanbanBoardsAPI.getSettings).toHaveBeenCalledWith(10);
    expect(KanbanBoardsAPI.showBoard).toHaveBeenCalledWith(10);
    expect(dispatch).toHaveBeenCalledWith('agents/get');
    expect(dispatch).toHaveBeenCalledWith('inboxes/get');
    expect(wrapper.find('[data-testid="kanban-settings-form"]').exists()).toBe(
      true
    );
  });

  it('renders stages in the settings page', async () => {
    const { wrapper } = await mountSettings();

    const stages = wrapper.findAll('[data-testid="kanban-settings-stage-row"]');
    expect(stages).toHaveLength(2);
    expect(stages[0].text()).toContain('Lead');
    expect(stages[1].text()).toContain('Won');
  });

  it('renders stage card counts in the settings page', async () => {
    const { wrapper } = await mountSettings();

    const counts = wrapper.findAll(
      '[data-testid="kanban-settings-stage-card-count"]'
    );
    expect(counts).toHaveLength(2);
    expect(counts[0].text()).toBe('3');
    expect(counts[1].text()).toBe('0');
  });

  it('creates a new stage from settings', async () => {
    const { wrapper, dispatch } = await mountSettings();

    await wrapper
      .find('[data-testid="kanban-settings-create-stage-toggle"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-settings-new-stage-name"]')
      .setValue('Follow up');
    await wrapper
      .find('[data-testid="kanban-settings-create-stage"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Follow up',
        color: 'slate',
        position: 3,
      },
    });
    expect(dispatch).toHaveBeenCalledWith('kanbanBoards/refreshBoards');
  });

  it('persists stage reorder from settings', async () => {
    const { wrapper, dispatch } = await mountSettings();
    const draggable = wrapper.findComponent({ name: 'Draggable' });

    await draggable.vm.$emit('end', {
      item: { dataset: { stageId: '200' } },
      oldIndex: 1,
      newIndex: 0,
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderStage).toHaveBeenCalledWith(10, 200, {
      position: 1,
    });
    expect(dispatch).toHaveBeenCalledWith('kanbanBoards/refreshBoards');
  });

  it('fills the form with the current payload', async () => {
    const { wrapper } = await mountSettings();

    expect(
      wrapper.find('[data-testid="kanban-settings-name"]').element.value
    ).toBe('Vendas');
    expect(
      wrapper.find('[data-testid="kanban-settings-description"]').element.value
    ).toBe('Pipeline comercial');
    expect(
      wrapper.find('[data-testid="kanban-settings-auto-create"]').element
        .checked
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-settings-agent-select"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-settings-inbox-select"]').exists()
    ).toBe(true);
  });

  it('toggles all_agents and selected_agents controls', async () => {
    const { wrapper } = await mountSettings();

    await wrapper.find('[data-testid="kanban-settings-all-agents"]').setValue();
    expect(
      wrapper.find('[data-testid="kanban-settings-agent-select"]').exists()
    ).toBe(false);

    await wrapper
      .find('[data-testid="kanban-settings-selected-agents"]')
      .setValue();
    expect(
      wrapper.find('[data-testid="kanban-settings-agent-select"]').exists()
    ).toBe(true);
  });

  it('toggles all_inboxes and selected_inboxes controls', async () => {
    const { wrapper } = await mountSettings();

    await wrapper
      .find('[data-testid="kanban-settings-all-inboxes"]')
      .setValue();
    expect(
      wrapper.find('[data-testid="kanban-settings-inbox-select"]').exists()
    ).toBe(false);

    await wrapper
      .find('[data-testid="kanban-settings-selected-inboxes"]')
      .setValue();
    expect(
      wrapper.find('[data-testid="kanban-settings-inbox-select"]').exists()
    ).toBe(true);
  });

  it('shows the automation toggle in the automations section', async () => {
    const { wrapper } = await mountSettings();

    expect(wrapper.text()).toContain('KANBAN.SETTINGS.AUTOMATIONS.TITLE');
    expect(wrapper.text()).toContain('KANBAN.SETTINGS.AUTOMATIONS.AUTO_CREATE');
    expect(
      wrapper.find('[data-testid="kanban-settings-auto-create"]').exists()
    ).toBe(true);
  });

  it('opens import modal when enabling auto-create', async () => {
    const { wrapper } = await mountSettings({
      getSettingsResponse: {
        data: {
          ...settingsPayload,
          auto_create_cards_from_conversations: false,
        },
      },
    });

    await wrapper
      .find('[data-testid="kanban-settings-auto-create"]')
      .setValue(true);
    await flushPromises();

    expect(KanbanBoardsAPI.updateSettings).toHaveBeenCalledWith(
      10,
      expect.objectContaining({
        kanban_board: expect.objectContaining({
          auto_create_cards_from_conversations: true,
        }),
      })
    );
    expect(
      wrapper
        .find('[data-testid="kanban-import-existing-conversations-modal"]')
        .exists()
    ).toBe(true);
    expect(wrapper.text()).toContain(
      'KANBAN.SETTINGS.AUTOMATIONS.IMPORT_EXISTING'
    );
    expect(wrapper.text()).toContain(
      'KANBAN.SETTINGS.AUTOMATIONS.IGNORE_GROUPS'
    );
  });

  it('closes import modal without calling import when skipping', async () => {
    const { wrapper } = await mountSettings({
      getSettingsResponse: {
        data: {
          ...settingsPayload,
          auto_create_cards_from_conversations: false,
        },
      },
    });

    await wrapper
      .find('[data-testid="kanban-settings-auto-create"]')
      .setValue(true);
    await flushPromises();
    await wrapper.find('[data-testid="kanban-import-skip"]').trigger('click');

    expect(KanbanBoardsAPI.importExistingConversations).not.toHaveBeenCalled();
    expect(
      wrapper
        .find('[data-testid="kanban-import-existing-conversations-modal"]')
        .exists()
    ).toBe(false);
  });

  it('imports existing conversations with ignore_groups', async () => {
    const { wrapper } = await mountSettings({
      getSettingsResponse: {
        data: {
          ...settingsPayload,
          auto_create_cards_from_conversations: false,
        },
      },
    });

    await wrapper
      .find('[data-testid="kanban-settings-auto-create"]')
      .setValue(true);
    await flushPromises();
    await wrapper
      .find('[data-testid="kanban-import-ignore-groups"]')
      .setValue();
    await wrapper
      .find('[data-testid="kanban-import-existing-conversations"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.importExistingConversations).toHaveBeenCalledWith(
      10,
      { ignore_groups: true }
    );
    expect(useAlert).toHaveBeenCalledWith(
      'KANBAN.SETTINGS.AUTOMATIONS.IMPORT_SUCCESS'
    );
    expect(
      wrapper
        .find('[data-testid="kanban-import-existing-conversations-modal"]')
        .exists()
    ).toBe(false);
  });

  it('keeps import modal open on import error', async () => {
    KanbanBoardsAPI.importExistingConversations.mockRejectedValueOnce(
      new Error('Failed')
    );
    const { wrapper } = await mountSettings({
      getSettingsResponse: {
        data: {
          ...settingsPayload,
          auto_create_cards_from_conversations: false,
        },
      },
    });

    await wrapper
      .find('[data-testid="kanban-settings-auto-create"]')
      .setValue(true);
    await flushPromises();
    await wrapper
      .find('[data-testid="kanban-import-existing-conversations"]')
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="kanban-import-error"]').exists()).toBe(
      true
    );
    expect(
      wrapper
        .find('[data-testid="kanban-import-existing-conversations-modal"]')
        .exists()
    ).toBe(true);
  });

  it('has pt_BR automation import translations', () => {
    expect(ptBRKanbanMessages.KANBAN.SETTINGS.AUTOMATIONS).toMatchObject({
      TITLE: 'Automações',
      AUTO_CREATE: 'Criar cartões automaticamente para novas conversas',
      IMPORT_EXISTING: 'Importar conversas existentes',
      IGNORE_GROUPS: 'Ignorar grupos',
      SKIP_IMPORT: 'Não importar agora',
    });
  });

  it('saves the expected payload', async () => {
    const { wrapper } = await mountSettings();

    await wrapper.find('[data-testid="kanban-settings-name"]').setValue('Novo');
    await wrapper
      .find('[data-testid="kanban-settings-description"]')
      .setValue('Funil novo');
    await wrapper
      .find('[data-testid="kanban-settings-auto-create"]')
      .setValue(false);
    await wrapper
      .findAll('[data-testid="tag-select-update"]')[0]
      .trigger('click');
    await wrapper
      .findAll('[data-testid="tag-select-update"]')[1]
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-settings-form"]')
      .trigger('submit');

    expect(KanbanBoardsAPI.updateSettings).toHaveBeenCalledWith(10, {
      kanban_board: {
        name: 'Novo',
        description: 'Funil novo',
        auto_create_cards_from_conversations: false,
        visibility_mode: 'selected_agents',
        visible_user_ids: [1, 2],
        inbox_scope_mode: 'selected_inboxes',
        allowed_inbox_ids: [5, 6],
      },
    });
  });

  it('preserves the filled form after save error', async () => {
    KanbanBoardsAPI.updateSettings.mockRejectedValueOnce(new Error('Failed'));
    const { wrapper } = await mountSettings();

    await wrapper.find('[data-testid="kanban-settings-name"]').setValue('Novo');
    await wrapper
      .find('[data-testid="kanban-settings-form"]')
      .trigger('submit');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-settings-name"]').element.value
    ).toBe('Novo');
    expect(
      wrapper.find('[data-testid="kanban-settings-save-error"]').exists()
    ).toBe(true);
  });

  it('refreshes boards after saving', async () => {
    const { wrapper, dispatch } = await mountSettings();

    await wrapper
      .find('[data-testid="kanban-settings-form"]')
      .trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('kanbanBoards/refreshBoards');
    expect(useAlert).toHaveBeenCalledWith('KANBAN.SETTINGS.SAVE_SUCCESS');
  });

  it('deletes the board and navigates to overview', async () => {
    const { wrapper, dispatch } = await mountSettings();

    await wrapper
      .find('[data-testid="kanban-settings-delete"]')
      .trigger('click');
    await wrapper.find('[data-testid="confirm-delete"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.delete).toHaveBeenCalledWith(10);
    expect(dispatch).toHaveBeenCalledWith('kanbanBoards/refreshBoards');
    expect(mockReplace).toHaveBeenCalledWith({
      name: 'kanban_boards',
      params: { accountId: '1' },
    });
  });

  it('does not show an editable form for agents', async () => {
    const { wrapper } = await mountSettings({
      role: 'agent',
      getSettingsError: {
        response: { status: 401, data: { error: 'Unauthorized' } },
      },
    });

    expect(wrapper.find('[data-testid="kanban-settings-form"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="kanban-settings-error"]').exists()).toBe(
      true
    );
  });
});
