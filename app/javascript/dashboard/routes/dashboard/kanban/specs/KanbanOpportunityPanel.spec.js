import { flushPromises, mount } from '@vue/test-utils';
import camelcaseKeys from 'camelcase-keys';
import { nextTick } from 'vue';
import KanbanOpportunityPanel from '../opportunity/KanbanOpportunityPanel.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const storeMocks = vi.hoisted(() => ({
  labels: [],
  dispatch: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) => {
      const translations = {
        'KANBAN.OPPORTUNITY_DETAILS.TABS.GENERAL': 'General',
        'KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS': 'Products',
        'KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA': 'Additional data',
        'KANBAN.OPPORTUNITY_DETAILS.AUTOSAVED_TAB': 'Saved automatically',
        'KANBAN.OPPORTUNITY_DETAILS.SAVED_AGO': 'Saved {time}',
        'KANBAN.OPPORTUNITY_DETAILS.UNSAVED_STATE': 'Unsaved',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING_STATE': 'Saving...',
        'KANBAN.OPPORTUNITY_DETAILS.NO_CHANGES': 'No changes to save',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD':
          'Could not save the opportunity fields.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_LABELS':
          'The opportunity was saved, but the labels were not.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_ASSIGNEES':
          'The opportunity was saved, but the agents were not.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_FIELDS':
          'The opportunity was saved, but the additional data was not.',
        'KANBAN.OPPORTUNITY_DETAILS.UNSAVED_FIELDS_MESSAGE':
          'You changed: {fields}.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_CHANGES': 'Save changes',
        'KANBAN.OPPORTUNITY_DETAILS.TITLE': 'Edit Opportunity',
        'KANBAN.OPPORTUNITY_DETAILS.CARD_ID': '#{id}',
        'KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID': 'Copy card ID',
        'KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED': 'Card ID copied.',
        'KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE': 'Subject',
        'KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION': 'Description',
        'KANBAN.OPPORTUNITY_DETAILS.DESCRIPTION_PLACEHOLDER':
          'Add a single note for this card',
        'KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE': 'Agent',
        'KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED': 'Unassigned',
        'KANBAN.OPPORTUNITY_DETAILS.NO_ASSIGNABLE_USERS': 'No agents available',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_ASSIGNEES_ERROR':
          'Could not load assignees.',
        'KANBAN.ACTIONS.REMOVE_CARD': 'Remove',
        'KANBAN.OPPORTUNITY_DETAILS.PRIORITY': 'Priority',
        'KANBAN.OPPORTUNITY_DETAILS.PRIORITY_NONE': 'No priority',
        'CONVERSATION.PRIORITY.OPTIONS.URGENT': 'Urgent',
        'CONVERSATION.PRIORITY.OPTIONS.HIGH': 'High',
        'CONVERSATION.PRIORITY.OPTIONS.MEDIUM': 'Medium',
        'CONVERSATION.PRIORITY.OPTIONS.LOW': 'Low',
        'KANBAN.OPPORTUNITY_DETAILS.CONVERSATION': 'Conversation',
        'KANBAN.OPPORTUNITY_DETAILS.CONVERSATION_ID': 'Conversation #{id}',
        'KANBAN.OPPORTUNITY_DETAILS.NO_INBOX': 'No inbox linked',
        'KANBAN.OPPORTUNITY_DETAILS.CONTACT': 'Contact',
        'KANBAN.OPPORTUNITY_DETAILS.NO_CONTACT': 'No contact linked',
        'KANBAN.OPPORTUNITY_DETAILS.DATES': 'Dates',
        'KANBAN.OPPORTUNITY_DETAILS.DUE_DATE': 'Due date',
        'KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE': 'Escolha a data',
        'KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE': 'Clear due date',
        'KANBAN.OPPORTUNITY_DETAILS.CANCEL': 'Cancel',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE': 'Save',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING': 'Saving...',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS': 'Opportunity saved.',
        'KANBAN.OPPORTUNITY_DETAILS.LABELS': 'Labels',
        'KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED': 'No labels selected',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_LABELS_ERROR':
          'Could not load labels.',
        'KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION': 'Open conversation',
        'KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION':
          'No linked conversation',
        'KANBAN.OPPORTUNITY_DETAILS.LOADING': 'Loading opportunity details...',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR':
          'Could not load opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR':
          'Could not save opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE': 'Subject is required.',
        'KANBAN.OPPORTUNITY_DETAILS.CLOSE': 'Close opportunity details',
      };

      return Object.entries(params).reduce(
        (message, [name, value]) =>
          message.replace(`{${name}}`, value).replace(`#{${name}}`, value),
        translations[key] || key
      );
    },
  }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    showCardById: vi.fn(),
    updateCardById: vi.fn(),
    updateCardDetailsById: vi.fn(),
    getCardLabels: vi.fn(),
    updateCardLabels: vi.fn(),
    getCardAssignees: vi.fn(),
    updateCardAssignees: vi.fn(),
    getCardProducts: vi.fn(),
    getCardFieldValues: vi.fn(),
    createCardProduct: vi.fn(),
    updateCardProduct: vi.fn(),
    deleteCardProduct: vi.fn(),
  },
}));

vi.mock('dashboard/api/products', () => ({
  default: {
    search: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: { value: false } }),
}));

vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await vi.importActual('vue');

  return {
    useStore: () => ({ dispatch: storeMocks.dispatch }),
    useMapGetter: () => computed(() => storeMocks.labels),
    useStoreGetters: () => ({ getCurrentRole: computed(() => 'agent') }),
  };
});

const nextInputStub = {
  inheritAttrs: false,
  props: ['modelValue', 'label', 'message', 'messageType', 'type', 'autofocus'],
  emits: ['update:modelValue', 'input'],
  template: `
    <label>
      <span>{{ label }}</span>
      <input
        v-bind="$attrs"
        :type="type || 'text'"
        :value="modelValue"
        @input="$emit('update:modelValue', $event.target.value); $emit('input', $event)"
      />
      <p v-if="message" :data-message-type="messageType">{{ message }}</p>
    </label>
  `,
};

const nextButtonStub = {
  props: ['label', 'disabled', 'isLoading', 'icon'],
  emits: ['click'],
  template: `
    <button
      v-bind="$attrs"
      :disabled="disabled"
      :data-icon="icon"
      @click="$emit('click', $event)"
    >
      <span v-if="isLoading">loading</span>
      {{ label }}
    </button>
  `,
};

const dueDatePickerStub = {
  name: 'KanbanDueDatePicker',
  inheritAttrs: false,
  props: ['modelValue', 'label', 'placeholder', 'clearLabel'],
  emits: ['update:modelValue', 'change'],
  template: `
    <label>
      <span>{{ label }}</span>
      <button v-bind="$attrs" type="button">
        {{ modelValue || placeholder }}
      </button>
      <button
        type="button"
        data-testid="kanban-clear-due-date"
        :aria-label="clearLabel"
        @click="$emit('update:modelValue', ''); $emit('change', '')"
      >
        clear
      </button>
    </label>
  `,
};

const editorStub = {
  name: 'Editor',
  inheritAttrs: false,
  props: ['modelValue', 'placeholder', 'showCharacterCount'],
  emits: ['update:modelValue'],
  template: `
    <textarea
      v-bind="$attrs"
      :value="modelValue"
      :placeholder="placeholder"
      @input="$emit('update:modelValue', $event.target.value)"
    />
  `,
};

const popoverStub = {
  name: 'Popover',
  props: ['align', 'disableMobileView', 'showContentBorder'],
  template: `
    <div>
      <slot />
      <slot name="content" />
    </div>
  `,
};

const labelDropdownStub = {
  name: 'LabelDropdown',
  props: ['accountLabels', 'selectedLabels', 'allowCreation'],
  emits: ['add', 'remove'],
  template: `
    <div data-testid="kanban-label-dropdown">
      <button
        v-for="label in accountLabels"
        :key="label.title"
        type="button"
        data-testid="kanban-label-dropdown-option"
        :data-selected="selectedLabels.includes(label.title)"
        @click="selectedLabels.includes(label.title) ? $emit('remove', label.title) : $emit('add', label)"
      >
        {{ label.title }}
      </button>
    </div>
  `,
};

const buildCard = overrides => ({
  id: 501,
  subject: 'Enterprise expansion',
  description: 'Follow up with procurement next week.',
  dueAt: '2026-06-05T18:00',
  conversationId: 42,
  conversation: {
    id: 42,
    meta: { assignee: { id: 7, name: 'Jane Agent' } },
  },
  inbox: { id: 3, name: 'Sales Inbox', channel_type: 'Channel::Email' },
  contact: { id: 91, name: 'Acme Buyer' },
  ...overrides,
});

const labels = [
  { id: 1, title: 'hot', color: '#ff0000' },
  { id: 2, title: 'enterprise', color: '#00ff00' },
];

const assignableUsers = [
  { id: 7, name: 'Jane Agent', avatar_url: 'jane.png' },
  { id: 8, name: 'John Agent', avatar_url: 'john.png' },
];

const tabBarStub = {
  name: 'TabBar',
  props: ['tabs', 'initialActiveTab'],
  emits: ['tabChanged'],
  template: `
    <div>
      <button
        v-for="(tab, index) in tabs"
        :key="index"
        type="button"
        :data-testid="'kanban-opportunity-tab-' + index"
        @click="$emit('tabChanged', tab)"
      >
        {{ tab.label }}
      </button>
    </div>
  `,
};

const mountModal = async ({
  card = buildCard(),
  resolveLoad = true,
  resolveProducts = true,
  accountLabels = labels,
  assignedLabels = [labels[0]],
  assignedUsers = [assignableUsers[0]],
  availableAssignableUsers = assignableUsers,
  cardProducts = [],
  customFields = [],
  wonStageId = null,
  lostStageId = null,
  lostReasonRequired = false,
  reasons = [],
  stages = [],
  moveToStage = vi.fn().mockResolvedValue(true),
  hasBlockingDialog = false,
} = {}) => {
  storeMocks.labels = accountLabels;
  storeMocks.dispatch.mockResolvedValue();

  const cardPayload = {
    ...card,
    labels: card.labels ?? assignedLabels,
    assignees: card.assignees ?? assignedUsers,
    assignable_users: card.assignable_users ?? availableAssignableUsers,
  };

  KanbanBoardsAPI.getCardFieldValues.mockResolvedValue({
    data: { payload: [] },
  });

  if (resolveProducts) {
    KanbanBoardsAPI.getCardProducts.mockResolvedValue({ data: cardProducts });
  }

  if (resolveLoad) {
    KanbanBoardsAPI.showCardById.mockResolvedValue({ data: cardPayload });
  }

  const wrapper = mount(KanbanOpportunityPanel, {
    props: {
      boardId: 10,
      cardId: 501,
      customFields,
      wonStageId,
      lostStageId,
      lostReasonRequired,
      reasons,
      stages,
      moveToStage,
      hasBlockingDialog,
    },
    global: {
      stubs: {
        NextInput: nextInputStub,
        NextButton: nextButtonStub,
        KanbanDueDatePicker: dueDatePickerStub,
        Popover: popoverStub,
        LabelDropdown: labelDropdownStub,
        Editor: editorStub,
        TabBar: tabBarStub,
      },
    },
  });

  if (resolveLoad) await flushPromises();

  return wrapper;
};

const subjectInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-subject"]');
const descriptionInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-description"]');
const dueAtInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-due-at"]');
const dueAtPicker = wrapper =>
  wrapper.findComponent({ name: 'KanbanDueDatePicker' });
const setDueAt = async (wrapper, value) => {
  dueAtPicker(wrapper).vm.$emit('update:modelValue', value);
  await nextTick();
};
const saveButton = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-save"]');
const labelButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-opportunity-label"]');
const labelDropdownOptions = wrapper =>
  wrapper.findAll('[data-testid="kanban-label-dropdown-option"]');

describe('KanbanOpportunityPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeMocks.labels = [];
    copyTextToClipboard.mockResolvedValue();
  });

  it('loads detail through showCardById', async () => {
    await mountModal();

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
  });

  it('renders a responsive two-column layout with more space for description', async () => {
    const wrapper = await mountModal();

    expect(wrapper.text()).toContain('Enterprise expansion');
    const panel = wrapper.find('[data-testid="kanban-opportunity-panel"]');
    expect(panel.attributes('role')).toBe('dialog');
    expect(panel.attributes('aria-modal')).toBe('true');
    expect(panel.attributes('aria-labelledby')).toBe(
      'kanban-opportunity-title'
    );
    expect(
      wrapper.find('[data-testid="kanban-opportunity-form"]').classes()
    ).toContain('grid');
    expect(
      wrapper.find('[data-testid="kanban-opportunity-layout"]').classes()
    ).toContain('xl:grid-cols-[minmax(0,1fr)_minmax(16rem,18rem)]');
  });

  it('keeps the context rail visible when switching tabs', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-context-rail"]').exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-1"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="kanban-opportunity-context-rail"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-contact"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-general-tab"]').isVisible()
    ).toBe(false);
  });

  it('renders title and description controls at full width', async () => {
    const wrapper = await mountModal();

    expect(subjectInput(wrapper).classes()).toContain('w-full');
    expect(descriptionInput(wrapper).classes()).toEqual(
      expect.arrayContaining(['max-w-full', 'w-full'])
    );
  });

  it('renders card ID in the header', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-card-id"]').text()
    ).toContain('#501');
    expect(
      wrapper.find('[data-testid="kanban-opportunity-close"]').exists()
    ).toBe(true);
  });

  it('copies card ID from the header', async () => {
    const wrapper = await mountModal();

    await wrapper
      .find('[data-testid="kanban-opportunity-copy-card-id"]')
      .trigger('click');

    expect(copyTextToClipboard).toHaveBeenCalledWith(501);
    expect(useAlert).toHaveBeenCalledWith('Card ID copied.');
  });

  it('renders loading state', async () => {
    KanbanBoardsAPI.showCardById.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(KanbanOpportunityPanel, {
      props: {
        boardId: 10,
        cardId: 501,
        moveToStage: vi.fn(),
      },
      global: {
        stubs: {
          NextInput: nextInputStub,
          NextButton: nextButtonStub,
        },
      },
    });

    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-loading"]').exists()
    ).toBe(true);
  });

  it('renders load error', async () => {
    KanbanBoardsAPI.showCardById.mockRejectedValue({
      response: { data: { message: 'Load failed' } },
    });
    const wrapper = await mountModal({ resolveLoad: false });

    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-load-error"]').text()
    ).toContain('Load failed');
  });

  it('loads subject', async () => {
    const wrapper = await mountModal();

    expect(subjectInput(wrapper).element.value).toBe('Enterprise expansion');
  });

  it('loads description', async () => {
    const wrapper = await mountModal();

    expect(descriptionInput(wrapper).element.value).toBe(
      'Follow up with procurement next week.'
    );
  });

  it('loads dueAt as a date only and removes startsAt', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-starts-at"]').exists()
    ).toBe(false);
    expect(dueAtPicker(wrapper).props('modelValue')).toBe('2026-06-05');
    expect(dueAtInput(wrapper).text()).toBe('2026-06-05');
  });

  it('loads priority into the dropdown', async () => {
    const wrapper = await mountModal({ card: buildCard({ priority: 'high' }) });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-priority"]').text()
    ).toContain('High');
  });

  it('saves priority', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ priority: 'urgent' }),
    });
    const wrapper = await mountModal();

    await wrapper
      .findAll('[data-testid="kanban-priority-option"]')
      .find(option => option.text().includes('Urgent'))
      .trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ priority: 'urgent' })
    );
  });

  it('saves description with existing scalar fields', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ description: 'Updated card note' }),
    });
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('Updated card note');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({
        subject: 'Enterprise expansion',
        description: 'Updated card note',
      })
    );
  });

  it('clears description with null', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ description: null }),
    });
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ description: null })
    );
  });

  it('preserves edited text on save error', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockRejectedValue({
      response: { data: { message: 'Save failed' } },
    });
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Preserved subject');
    await descriptionInput(wrapper).setValue('Preserved description');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(subjectInput(wrapper).element.value).toBe('Preserved subject');
    expect(descriptionInput(wrapper).element.value).toBe(
      'Preserved description'
    );
    expect(
      wrapper.find('[data-testid="kanban-opportunity-save-error"]').text()
    ).toContain('Could not save the opportunity fields.');
  });

  it('saves due date without touching start date', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    const wrapper = await mountModal();

    await setDueAt(wrapper, '2026-06-04');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({
        due_at: new Date(2026, 5, 4, 12).toISOString(),
      })
    );
    expect(
      KanbanBoardsAPI.updateCardDetailsById.mock.calls[0][2]
    ).not.toHaveProperty('starts_at');
  });

  it('clears due date with null', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ dueAt: null }),
    });
    const wrapper = await mountModal();

    await setDueAt(wrapper, '');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ due_at: null })
    );
  });

  it('rejects blank title locally', async () => {
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('   ');
    await wrapper.find('form').trigger('submit');

    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Subject is required.');
  });

  it('disables save while pending', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockReturnValue(
      new Promise(() => {})
    );
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Pending subject');
    await wrapper.find('form').trigger('submit');

    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();

    await wrapper.find('form').trigger('submit');
    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledTimes(1);
  });

  it('emits updated on successful save', async () => {
    const updatedCard = buildCard({
      subject: 'Updated subject',
      description: 'Updated note',
    });
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: updatedCard,
    });
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Updated subject');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.emitted('updated')[0][0]).toMatchObject(
      camelcaseKeys(updatedCard, { deep: true })
    );
    expect(useAlert).toHaveBeenCalledWith('Opportunity saved.');
  });
  it('keeps the savebar visible and disables saving without changes', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-savebar"]').exists()
    ).toBe(true);
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
    expect(saveButton(wrapper).attributes('title')).toBe('No changes to save');
    expect(
      wrapper.find('[data-testid="kanban-opportunity-save-state"]').text()
    ).toContain('Saved');
  });

  it('saves in order and stops when the labels step fails', async () => {
    const calls = [];
    KanbanBoardsAPI.updateCardDetailsById.mockImplementation(async () => {
      calls.push('card');
      return { data: buildCard({ subject: 'Updated subject' }) };
    });
    KanbanBoardsAPI.updateCardLabels.mockImplementation(async () => {
      calls.push('labels');
      throw new Error('Labels failed');
    });
    KanbanBoardsAPI.updateCardAssignees.mockImplementation(async () => {
      calls.push('assignees');
      return { data: { payload: assignableUsers } };
    });
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Updated subject');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(calls).toEqual(['card', 'labels']);
    expect(KanbanBoardsAPI.updateCardAssignees).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-save-error"]').text()
    ).toContain('the labels were not');
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-unsaved-indicator"]')
        .exists()
    ).toBe(true);
  });

  it('marks the general tab when a card field is dirty', async () => {
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Updated subject');

    expect(
      wrapper.findComponent({ name: 'TabBar' }).props('tabs')[0].label
    ).toBe('General •');
  });

  it('saves with the Ctrl+S shortcut', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ subject: 'Shortcut subject' }),
    });
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Shortcut subject');
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 's', ctrlKey: true })
    );
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ subject: 'Shortcut subject' })
    );
  });

  it('renders linked conversation inbox and open action', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-conversation"]').text()
    ).toContain('Sales Inbox');
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-conversation"]')
        .findComponent({ name: 'ChannelIcon' })
        .props('inbox')
    ).toEqual(camelcaseKeys(buildCard().inbox, { deep: true }));
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-open-conversation"]')
        .text()
    ).toContain('Open conversation');
  });

  it('emits open conversation with card payload', async () => {
    const card = buildCard();
    const wrapper = await mountModal({ card });

    await wrapper
      .find('[data-testid="kanban-opportunity-open-conversation"]')
      .trigger('click');

    expect(wrapper.emitted('openConversation')[0][0]).toMatchObject(
      camelcaseKeys(card, { deep: true })
    );
  });

  it('renders no linked conversation for unlinked card', async () => {
    const wrapper = await mountModal({
      card: buildCard({ conversationId: null, conversation: null }),
    });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-no-conversation"]').text()
    ).toContain('No linked conversation');
  });

  it('renders linked contact', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-contact"]').text()
    ).toContain('Acme Buyer');
  });

  it('renders a contact avatar with initials fallback when there is no photo', async () => {
    const wrapper = await mountModal();
    const contact = wrapper
      .find('[data-testid="kanban-opportunity-contact"]')
      .findComponent({ name: 'Avatar' });

    expect(contact.exists()).toBe(true);
    expect(contact.props('name')).toBe('Acme Buyer');
    expect(contact.text()).toContain('AB');
  });

  it('renders the contact photo when a thumbnail is available', async () => {
    const wrapper = await mountModal({
      card: buildCard({
        contact: { id: 91, name: 'Acme Buyer', thumbnail: 'acme.png' },
      }),
    });
    const contact = wrapper
      .find('[data-testid="kanban-opportunity-contact"]')
      .findComponent({ name: 'Avatar' });

    expect(contact.props('src')).toBe('acme.png');
  });

  it('renders a generic icon when there is no linked contact', async () => {
    const wrapper = await mountModal({
      card: buildCard({ contact: null }),
    });

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-contact"]')
        .findComponent({ name: 'Avatar' })
        .exists()
    ).toBe(false);
  });

  it('loads card context from showCardById without separate requests', async () => {
    const wrapper = await mountModal({
      assignedLabels: labels,
      assignedUsers: assignableUsers,
    });

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
    expect(KanbanBoardsAPI.getCardLabels).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getCardAssignees).not.toHaveBeenCalled();
    expect(
      wrapper.findAll('[data-testid="kanban-opportunity-assignee"]')
    ).toHaveLength(2);
    expect(labelButtons(wrapper)).toHaveLength(2);
  });

  it('renders assigned users as chips', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-assignee"]').text()
    ).toContain('Jane Agent');
  });

  it('renders unassigned state when no one is assigned', async () => {
    const wrapper = await mountModal({ assignedUsers: [] });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-no-assignees"]').text()
    ).toContain('Unassigned');
  });

  it('lists assignable users in the dropdown', async () => {
    const wrapper = await mountModal();
    const options = wrapper.findAll(
      '[data-testid="kanban-opportunity-assignee-option"]'
    );

    expect(options).toHaveLength(2);
    expect(options[0].attributes('data-selected')).toBe('true');
    expect(options[1].attributes('data-selected')).toBe('false');
  });

  it('toggles an assignee locally without saving immediately', async () => {
    const wrapper = await mountModal();

    await wrapper
      .findAll('[data-testid="kanban-opportunity-assignee-option"]')[1]
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardAssignees).not.toHaveBeenCalled();
    expect(
      wrapper
        .findAll('[data-testid="kanban-opportunity-assignee-option"]')[1]
        .attributes('data-selected')
    ).toBe('true');
  });

  it('saves toggled assignees through updateCardAssignees on submit', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: [labels[0]] },
    });
    KanbanBoardsAPI.updateCardAssignees.mockResolvedValue({
      data: {
        payload: [assignableUsers[0], assignableUsers[1]],
        assignable_users: assignableUsers,
      },
    });
    const wrapper = await mountModal();

    await wrapper
      .findAll('[data-testid="kanban-opportunity-assignee-option"]')[1]
      .trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardAssignees).toHaveBeenCalledWith(
      10,
      501,
      [7, 8]
    );
  });

  it('does not load deferred tab data before a tab is opened', async () => {
    const wrapper = await mountModal();

    expect(KanbanBoardsAPI.getCardProducts).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getCardFieldValues).not.toHaveBeenCalled();
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-additional-data-tab"]')
        .exists()
    ).toBe(false);
  });

  it('loads each deferred tab once and preserves its mounted state', async () => {
    const wrapper = await mountModal();

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-1"]')
      .trigger('click');
    await flushPromises();
    expect(KanbanBoardsAPI.getCardProducts).toHaveBeenCalledTimes(1);
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-products-autosaved"]')
        .exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-0"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-opportunity-tab-1"]')
      .trigger('click');
    await flushPromises();
    expect(KanbanBoardsAPI.getCardProducts).toHaveBeenCalledTimes(1);

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-2"]')
      .trigger('click');
    await flushPromises();
    expect(KanbanBoardsAPI.getCardFieldValues).toHaveBeenCalledTimes(1);
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-additional-data-tab"]')
        .exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-0"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-opportunity-tab-2"]')
      .trigger('click');
    await flushPromises();
    expect(KanbanBoardsAPI.getCardFieldValues).toHaveBeenCalledTimes(1);
  });

  it('normalizes linked product payloads before rendering', async () => {
    const wrapper = await mountModal({
      cardProducts: [
        {
          id: 12,
          sku: 'SKU-1',
          name: 'Produto',
          quantity: 2,
          unit_price: 12.5,
          subtotal: 25,
        },
      ],
    });

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-1"]')
      .trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-linked-product"]').text()
    ).toContain('12,50');
    expect(
      wrapper.find('[data-testid="kanban-opportunity-products-total"]').text()
    ).toContain('25,00');
  });

  it('renders label title and color', async () => {
    const wrapper = await mountModal();
    const firstLabel = labelButtons(wrapper)[0];

    expect(firstLabel.text()).toContain('hot');
    expect(firstLabel.find('span').element.style.backgroundColor).toBe(
      'rgb(255, 0, 0)'
    );
  });

  it('renders assigned labels as selected chips and dropdown options', async () => {
    const wrapper = await mountModal();

    expect(labelButtons(wrapper)).toHaveLength(1);
    expect(labelDropdownOptions(wrapper)[0].attributes('data-selected')).toBe(
      'true'
    );
    expect(labelDropdownOptions(wrapper)[1].attributes('data-selected')).toBe(
      'false'
    );
  });

  it('toggles a label locally without saving immediately', async () => {
    const wrapper = await mountModal();

    await labelDropdownOptions(wrapper)[1].trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).not.toHaveBeenCalled();
    expect(labelButtons(wrapper)).toHaveLength(2);
  });

  it('saves toggled labels through updateCardLabels on submit', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: labels },
    });
    KanbanBoardsAPI.updateCardAssignees.mockResolvedValue({
      data: {
        payload: [assignableUsers[0]],
        assignable_users: assignableUsers,
      },
    });
    const wrapper = await mountModal();

    await labelDropdownOptions(wrapper)[1].trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledWith(10, 501, [
      'hot',
      'enterprise',
    ]);
  });

  it('preserves scalar form state when toggling a label without saving', async () => {
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Modified subject');
    await descriptionInput(wrapper).setValue('Modified description');
    await labelDropdownOptions(wrapper)[1].trigger('click');
    await flushPromises();

    expect(subjectInput(wrapper).element.value).toBe('Modified subject');
    expect(descriptionInput(wrapper).element.value).toBe(
      'Modified description'
    );
    expect(dueAtPicker(wrapper).props('modelValue')).toBe('2026-06-05');
  });

  it('does not render an add-note action', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-add-note"]').exists()
    ).toBe(false);
    expect(wrapper.text()).not.toContain('Add note');
  });

  it('emits close from cancel action', async () => {
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('Changed subject');
    await wrapper
      .find('[data-testid="kanban-opportunity-cancel"]')
      .trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('emits removeCard with the loaded card from the header delete action', async () => {
    const card = buildCard();
    const wrapper = await mountModal({ card });

    await wrapper
      .find('[data-testid="kanban-opportunity-remove-card"]')
      .trigger('click');

    expect(wrapper.emitted('removeCard')[0][0]).toMatchObject(
      camelcaseKeys(card, { deep: true })
    );
  });

  it('does not render the status badge when the board has no won/lost stages', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').exists()
    ).toBe(false);
  });

  it('updates status without discarding dirty form fields', async () => {
    KanbanBoardsAPI.updateCardById.mockResolvedValue({
      data: { ...buildCard(), kanban_stage_id: 20, kanban_reason_id: null },
    });

    const wrapper = await mountModal({
      card: buildCard({ kanban_stage_id: 15 }),
      wonStageId: 20,
      lostStageId: 30,
      reasons: [{ id: 1, title: 'Good fit', reason_type: 'won' }],
    });
    await subjectInput(wrapper).setValue('Edited subject');

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-card-status-option-won"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-card-status-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardById).toHaveBeenCalledWith(10, 501, {
      card: { kanban_stage_id: 20, kanban_reason_id: null },
    });
    expect(subjectInput(wrapper).element.value).toBe('Edited subject');
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-unsaved-indicator"]')
        .exists()
    ).toBe(true);
    expect(wrapper.emitted('updated')).toBeTruthy();
  });
  it('stands down from keyboard shortcuts while a blocking dialog is open', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({ data: [] });
    KanbanBoardsAPI.updateCardAssignees.mockResolvedValue({
      data: { payload: [] },
    });
    const wrapper = await mountModal({ hasBlockingDialog: true });

    await subjectInput(wrapper).setValue('Updated subject');
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 's', ctrlKey: true })
    );
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await flushPromises();

    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-unsaved-indicator"]')
        .exists()
    ).toBe(true);
  });

  it('does not trap tab while a blocking dialog is open', async () => {
    await mountModal({ hasBlockingDialog: true });
    const tabEvent = new KeyboardEvent('keydown', {
      key: 'Tab',
      cancelable: true,
    });

    document.dispatchEvent(tabEvent);

    expect(tabEvent.defaultPrevented).toBe(false);
  });

  it('moves the card to another stage through the injected action', async () => {
    const moveToStage = vi.fn().mockResolvedValue(true);
    const wrapper = await mountModal({
      card: buildCard({ kanbanStageId: 15 }),
      stages: [
        { id: 15, name: 'Prospecting' },
        { id: 16, name: 'Negotiation' },
      ],
      moveToStage,
    });

    wrapper
      .findComponent('[data-testid="kanban-opportunity-stage-select"]')
      .vm.$emit('update:modelValue', 16);
    await flushPromises();

    expect(moveToStage).toHaveBeenCalledWith(
      expect.objectContaining({ id: 501 }),
      16
    );
    expect(wrapper.emitted('moveToStage')).toBeUndefined();
  });

  it('reverts the stage select when the move is rejected', async () => {
    const moveToStage = vi.fn().mockResolvedValue(false);
    const wrapper = await mountModal({
      card: buildCard({ kanbanStageId: 15 }),
      stages: [
        { id: 15, name: 'Prospecting' },
        { id: 16, name: 'Negotiation' },
      ],
      moveToStage,
    });
    const select = wrapper.findComponent(
      '[data-testid="kanban-opportunity-stage-select"]'
    );

    select.vm.$emit('update:modelValue', 16);
    await flushPromises();

    expect(select.props('modelValue')).toBe(15);
  });
});
