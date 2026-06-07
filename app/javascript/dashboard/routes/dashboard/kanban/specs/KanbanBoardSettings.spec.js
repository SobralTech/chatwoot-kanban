import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import KanbanBoardSettings from '../KanbanBoardSettings.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';

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
    updateSettings: vi.fn(),
    delete: vi.fn(),
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
        WootDeleteModal: {
          props: ['show', 'onConfirm'],
          template:
            '<button v-if="show" data-testid="confirm-delete" type="button" @click="onConfirm" />',
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
  });

  it('loads the page settings', async () => {
    const { wrapper, dispatch } = await mountSettings();

    expect(KanbanBoardsAPI.getSettings).toHaveBeenCalledWith(10);
    expect(dispatch).toHaveBeenCalledWith('agents/get');
    expect(dispatch).toHaveBeenCalledWith('inboxes/get');
    expect(wrapper.find('[data-testid="kanban-settings-form"]').exists()).toBe(
      true
    );
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
