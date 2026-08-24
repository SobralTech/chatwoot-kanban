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
        'KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS': 'Products',
        'KANBAN.OPPORTUNITY_DETAILS.TABS.DETAILS': 'Details',
        'KANBAN.OPPORTUNITY_DETAILS.AUTOSAVED_TAB': 'Saved automatically',
        'KANBAN.OPPORTUNITY_DETAILS.SAVED_AGO': 'Saved {time}',
        'KANBAN.OPPORTUNITY_DETAILS.UNSAVED_STATE': 'Unsaved',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING_STATE': 'Saving...',
        'KANBAN.OPPORTUNITY_DETAILS.NO_CHANGES': 'No changes to save',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD':
          'Could not save the opportunity fields.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_FIELDS':
          'The opportunity was saved, but the additional data was not.',
        'KANBAN.OPPORTUNITY_DETAILS.UNSAVED_FIELDS_MESSAGE':
          'You changed: {fields}.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_CHANGES': 'Save changes',
        'KANBAN.OPPORTUNITY_DETAILS.TITLE': 'Edit Opportunity',
        'KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID_WITH_ID': 'Copy ID (#{id})',
        'KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED': 'Card ID copied.',
        'KANBAN.OPPORTUNITY_DETAILS.OPEN_IN_BOARD': 'Open in funnel',
        'KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_LINK': 'Copy card link',
        'KANBAN.OPPORTUNITY_DETAILS.CARD_LINK_COPIED': 'Card link copied.',
        'KANBAN.OPPORTUNITY_DETAILS.EDIT_SUBJECT': 'Edit subject',
        'KANBAN.OPPORTUNITY_DETAILS.SUBJECT_UPDATE_ERROR':
          'Could not update the subject.',
        'KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR':
          'Could not update the opportunity.',
        'KANBAN.CARD.LABELS_UPDATE_ERROR': 'Could not update the card labels.',
        'KANBAN.CARD.PRIORITY_UPDATE_ERROR':
          'Could not update the card priority.',
        'KANBAN.CARD.DUE_DATE_UPDATE_ERROR': 'Could not update the due date.',
        'KANBAN.CARD.ASSIGN_ERROR': 'Could not update the assignees.',
        'KANBAN.OPPORTUNITY_DETAILS.MORE_ITEMS': '+{count}',
        'KANBAN.OPPORTUNITY_DETAILS.REASON_LABEL': 'Reason: {reason}',
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
        'KANBAN.OPPORTUNITY_DETAILS.DUE_DATE': 'Due date',
        'KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE': 'Escolha a data',
        'KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE': 'Clear due date',
        'KANBAN.OPPORTUNITY_DETAILS.CANCEL': 'Cancel',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE': 'Save',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING': 'Saving...',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS': 'Opportunity saved.',
        'KANBAN.OPPORTUNITY_DETAILS.LABELS': 'Labels',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_LABELS_ERROR':
          'Could not load labels.',
        'KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION': 'Open conversation',
        'KANBAN.OPPORTUNITY_DETAILS.LOADING': 'Loading opportunity details...',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR':
          'Could not load opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR':
          'Could not save opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE': 'Subject is required.',
        'KANBAN.OPPORTUNITY_DETAILS.CLOSE': 'Close opportunity details',
        'KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL': 'Close opportunity details',
        'KANBAN.CARD.SLA_STALE': 'SLA exceeded',
        'KANBAN.CARD.SLA_TOOLTIP': '{age} / {hours} hours',
        'KANBAN.CARD.ACTIONS_MENU': 'Card actions',
        'KANBAN.CARD.UNKNOWN_CONTACT': 'Unknown contact',
        'KANBAN.CARD.UNKNOWN_INBOX': 'Unknown inbox',
        'KANBAN.CARD.OPEN_IN_NEW_TAB': 'Open in a new tab',
        'KANBAN.CARD.MOVE_TO': 'Move to',
        'KANBAN.CARD.MOVE_BOARD_LABEL': 'Funnel',
        'KANBAN.CARD.MOVE_CURRENT_STAGE': '{name} (current) — move to top',
        'KANBAN.CARD.NO_REGULAR_STAGES': 'No other stages available.',
        'KANBAN.CARD.MOVE_CONFIRM_CLEAN': 'The opportunity keeps all its data.',
        'KANBAN.CARD.MOVE_CONFIRM_REOPEN': 'The opportunity will be reopened.',
        'KANBAN.CARD.MOVE_CONFIRM_REASON':
          'The reason "{reason}" will be removed.',
        'KANBAN.CARD.MOVE_CONFIRM_FIELDS':
          '{count} of {total} custom fields do not exist in {board} and will be discarded: {keys}.',
        'KANBAN.CARD.MOVE_CONFIRM_CANCEL': 'Cancel',
        'KANBAN.CARD.MOVE_CONFIRM_SUBMIT': 'Move',
        'KANBAN.CARD.MOVE_SUCCESS': 'Card moved.',
        'KANBAN.CARD.MOVE_BOARD_ERROR': 'Could not move the opportunity.',
        'KANBAN.CARD.MOVE_BOARD_ERROR_DUPLICATE':
          '{board} already has an opportunity for this conversation.',
        'KANBAN.CARD.MOVE_BOARD_ERROR_INBOX':
          '{board} does not accept this inbox.',
        'KANBAN.MENU.BACK': 'Back',
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
    reorderCardById: vi.fn(),
    moveCardToBoard: vi.fn(),
    updateCardById: vi.fn(),
    reopenCardById: vi.fn(),
    updateCardDetailsById: vi.fn(),
    getCardLabels: vi.fn(),
    updateCardLabels: vi.fn(),
    getCardAssignees: vi.fn(),
    updateCardAssignees: vi.fn(),
    getCardProducts: vi.fn(),
    getCardFieldValues: vi.fn(),
    updateCardFieldValues: vi.fn(),
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
  cardFieldValues = [],
  customFields = [],
  wonStageId = null,
  lostStageId = null,
  lostReasonRequired = false,
  reasons = [],
  stages = [],
  moveToStage = vi.fn().mockResolvedValue(true),
  hasBlockingDialog = false,
  board = {},
  boards = [],
  openedFromConversation = false,
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
    data: { payload: cardFieldValues },
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
      boardName: 'Sales',
      board,
      boards,
      customFields,
      wonStageId,
      lostStageId,
      lostReasonRequired,
      reasons,
      stages,
      moveToStage,
      hasBlockingDialog,
      openedFromConversation,
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

const subjectTitle = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-title"]');
const subjectInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-title-input"] input');
const editSubject = async (wrapper, value) => {
  await subjectTitle(wrapper).trigger('click');
  await subjectInput(wrapper).setValue(value);
  await subjectInput(wrapper).trigger('keydown', { key: 'Enter' });
  await nextTick();
};
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
  const openHeaderMenu = async wrapper => {
    await wrapper
      .find('[data-testid="kanban-opportunity-more-actions"]')
      .trigger('click');
  };

  const headerMenuItems = wrapper =>
    wrapper.findAll('[data-testid="kanban-opportunity-actions-menu"] button');

  const headerMenuItem = (wrapper, label) =>
    headerMenuItems(wrapper).find(button => button.text().includes(label));

  const openMoveDialogFromHeader = async wrapper => {
    await wrapper
      .find('[data-testid="kanban-opportunity-move-to"]')
      .trigger('click');
  };

  const submitMoveToStage = async (wrapper, stageIndex) => {
    await wrapper
      .findAll('[data-testid="kanban-card-move-dialog-stage"]')
      [stageIndex].trigger('click');
    await wrapper
      .find('[data-testid="kanban-card-move-dialog-submit"]')
      .trigger('click');
    await flushPromises();
  };

  beforeEach(() => {
    vi.clearAllMocks();
    storeMocks.labels = [];
    copyTextToClipboard.mockResolvedValue();
  });

  it('loads detail through showCardById', async () => {
    await mountModal();

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
  });

  it('renders a single 640px opportunity layout with vertical scrolling', async () => {
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
    expect(panel.classes()).toContain('md:w-[min(40rem,100vw)]');
    expect(
      wrapper.find('[data-testid="kanban-opportunity-layout"]').classes()
    ).toContain('min-w-0');
    expect(wrapper.find('.overflow-y-auto').exists()).toBe(true);
  });

  it('keeps the new header visible when switching tabs', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-header"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-subtitle"]').text()
    ).toContain('Sales');

    await wrapper
      .find('[data-testid="kanban-opportunity-tab-1"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="kanban-opportunity-header"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-details-tab"]').isVisible()
    ).toBe(false);
  });

  it('renders title and description controls at full width', async () => {
    const wrapper = await mountModal();

    expect(descriptionInput(wrapper).classes()).toEqual(
      expect.arrayContaining(['max-w-full', 'w-full'])
    );
  });

  it('keeps the card ID out of the visible header and puts it in the menu label', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-card-id"]').exists()
    ).toBe(false);
    await openHeaderMenu(wrapper);
    expect(headerMenuItem(wrapper, 'Copy ID (#501)')).toBeTruthy();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-close"]').exists()
    ).toBe(true);
  });

  it('copies card ID from the header', async () => {
    const wrapper = await mountModal();

    await openHeaderMenu(wrapper);
    await headerMenuItem(wrapper, 'Copy ID (#501)').trigger('click');

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

    expect(subjectTitle(wrapper).text()).toContain('Enterprise expansion');
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

  it('persists priority immediately', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ priority: 'urgent' }),
    });
    const wrapper = await mountModal();

    await wrapper
      .findAll('[data-testid="kanban-priority-option"]')
      .find(option => option.text().includes('Urgent'))
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      { priority: 'urgent' }
    );
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
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
      { description: 'Updated card note' }
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

  it('preserves description text on save error', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockRejectedValue({
      response: { data: { message: 'Save failed' } },
    });
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('Preserved description');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(descriptionInput(wrapper).element.value).toBe(
      'Preserved description'
    );
    expect(
      wrapper.find('[data-testid="kanban-opportunity-save-error"]').text()
    ).toContain('Could not save the opportunity fields.');
  });

  it('persists due date without touching start date', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    const wrapper = await mountModal();

    await setDueAt(wrapper, '2026-06-04');
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

  it('clears due date immediately with null', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ dueAt: null }),
    });
    const wrapper = await mountModal();

    await setDueAt(wrapper, '');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ due_at: null })
    );
  });

  it('rejects blank title locally', async () => {
    const wrapper = await mountModal();

    await subjectTitle(wrapper).trigger('click');
    await subjectInput(wrapper).setValue('   ');
    await subjectInput(wrapper).trigger('keydown', { key: 'Enter' });
    await nextTick();

    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-subject-error"]').text()
    ).toContain('Subject is required.');
    expect(subjectInput(wrapper).exists()).toBe(true);
  });

  it('persists the subject immediately without dirtying the save bar', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: { subject: 'Updated subject' },
    });
    const wrapper = await mountModal();

    await editSubject(wrapper, 'Updated subject');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      { subject: 'Updated subject' }
    );
    expect(subjectTitle(wrapper).text()).toContain('Updated subject');
    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('discards inline subject edits with Escape', async () => {
    const wrapper = await mountModal();

    await subjectTitle(wrapper).trigger('click');
    await subjectInput(wrapper).setValue('Temporary subject');
    await subjectInput(wrapper).trigger('keydown', { key: 'Escape' });
    await nextTick();

    expect(subjectTitle(wrapper).text()).toContain('Enterprise expansion');
    expect(subjectInput(wrapper).exists()).toBe(false);
    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
  });

  it('rolls back the subject when its immediate update fails', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockRejectedValue({
      response: { data: { message: 'Subject failed' } },
    });
    const wrapper = await mountModal();

    await editSubject(wrapper, 'Rejected subject');
    await flushPromises();

    expect(subjectTitle(wrapper).text()).toContain('Enterprise expansion');
    expect(useAlert).toHaveBeenCalledWith('Could not update the subject.');
  });

  it('disables a quick field while its update is pending', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockReturnValue(
      new Promise(() => {})
    );
    const wrapper = await mountModal();

    await editSubject(wrapper, 'Pending subject');

    expect(subjectTitle(wrapper).attributes('aria-disabled')).toBe('true');
    await subjectTitle(wrapper).trigger('click');
    expect(subjectInput(wrapper).exists()).toBe(false);

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledTimes(1);
  });

  it('emits updated on successful save', async () => {
    const updatedCard = buildCard({
      description: 'Updated note',
    });
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: updatedCard,
    });
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('Updated note');
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

  it('marks the Details tab when description is dirty', async () => {
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('Updated description');

    expect(
      wrapper.findComponent({ name: 'TabBar' }).props('tabs')[0].label
    ).toBe('Details •');
  });

  it('saves with the Ctrl+S shortcut', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ subject: 'Shortcut subject' }),
    });
    const wrapper = await mountModal();

    await descriptionInput(wrapper).setValue('Shortcut description');
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 's', ctrlKey: true })
    );
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      { description: 'Shortcut description' }
    );
  });

  it('renders linked conversation inbox and open action', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-subtitle"]').text()
    ).toContain('Sales Inbox');
    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-subtitle"]')
        .findComponent({ name: 'ChannelIcon' })
        .props('inbox')
    ).toEqual(camelcaseKeys(buildCard().inbox, { deep: true }));
    await openHeaderMenu(wrapper);
    expect(headerMenuItem(wrapper, 'Open conversation')).toBeTruthy();
  });

  it('emits open conversation with card payload', async () => {
    const card = buildCard();
    const wrapper = await mountModal({ card });

    await openHeaderMenu(wrapper);
    await headerMenuItem(wrapper, 'Open conversation').trigger('click');

    expect(wrapper.emitted('openConversation')[0][0]).toMatchObject(
      camelcaseKeys(card, { deep: true })
    );
  });

  it('hides the inbox subtitle item for an unlinked card', async () => {
    const wrapper = await mountModal({
      card: buildCard({ conversationId: null, conversation: null }),
    });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-subtitle"]').text()
    ).not.toContain('No inbox linked');
    await openHeaderMenu(wrapper);
    expect(headerMenuItem(wrapper, 'Open conversation')).toBeUndefined();
  });

  it('renders linked contact', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-subtitle"]').text()
    ).toContain('Acme Buyer');
  });

  it('renders a contact avatar with initials fallback when there is no photo', async () => {
    const wrapper = await mountModal();
    const contact = wrapper
      .find('[data-testid="kanban-opportunity-subtitle"]')
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
      .find('[data-testid="kanban-opportunity-subtitle"]')
      .findComponent({ name: 'Avatar' });

    expect(contact.props('src')).toBe('acme.png');
  });

  it('renders a generic icon when there is no linked contact', async () => {
    const wrapper = await mountModal({
      card: buildCard({ contact: null }),
    });

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-subtitle"]')
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
      wrapper.find('[data-testid="kanban-opportunity-assignees-menu"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-assignees-menu"]').text()
    ).not.toContain('Unassigned');
  });

  it('renders the add-agent affordance when no one is assigned', async () => {
    const wrapper = await mountModal({ assignedUsers: [] });

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-assignees-menu"] i')
        .classes()
    ).toContain('i-lucide-user-plus');
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

  it('persists an assignee toggle immediately', async () => {
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
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardAssignees).toHaveBeenCalledWith(
      10,
      501,
      [7, 8]
    );
    expect(
      wrapper
        .findAll('[data-testid="kanban-opportunity-assignee-option"]')[1]
        .attributes('data-selected')
    ).toBe('true');
  });

  it('does not load custom field data when the board has no fields', async () => {
    const wrapper = await mountModal();

    expect(KanbanBoardsAPI.getCardProducts).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getCardFieldValues).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-details-tab"]').exists()
    ).toBe(true);
  });

  it('loads and saves custom fields inside Details', async () => {
    const customFields = [
      { id: 9, key: 'Segment', fieldType: 'text', multiple: false },
    ];
    const wrapper = await mountModal({
      customFields,
      cardFieldValues: [{ kanban_custom_field_id: 9, value: ['Enterprise'] }],
    });
    await flushPromises();
    const fieldInput = wrapper
      .findAll('input')
      .find(input => input.element.value === 'Enterprise');

    expect(fieldInput).toBeTruthy();
    await fieldInput.setValue('SMB');
    await nextTick();

    expect(saveButton(wrapper).attributes('disabled')).toBeUndefined();
    await wrapper.vm.saveCard();
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardFieldValues).toHaveBeenCalledWith(
      10,
      501,
      { field_values: { 9: ['SMB'] } }
    );
    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
  });

  it('loads Products on demand and keeps the Details tab available', async () => {
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
      .find('[data-testid="kanban-opportunity-tab-0"]')
      .trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-details-tab"]').exists()
    ).toBe(true);
    expect(KanbanBoardsAPI.getCardFieldValues).not.toHaveBeenCalled();
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

  it('persists a label toggle immediately', async () => {
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: labels },
    });
    const wrapper = await mountModal();

    await labelDropdownOptions(wrapper)[1].trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledWith(10, 501, [
      'hot',
      'enterprise',
    ]);
    expect(labelButtons(wrapper)).toHaveLength(2);
  });

  it('rolls back a label toggle when its immediate update fails', async () => {
    KanbanBoardsAPI.updateCardLabels.mockRejectedValue(
      new Error('Labels failed')
    );
    const wrapper = await mountModal();

    await labelDropdownOptions(wrapper)[1].trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledTimes(1);
    expect(labelButtons(wrapper)).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith('Could not update the card labels.');
  });

  it('preserves scalar form state when toggling a label without saving', async () => {
    const wrapper = await mountModal();

    await editSubject(wrapper, 'Modified subject');
    await descriptionInput(wrapper).setValue('Modified description');
    await labelDropdownOptions(wrapper)[1].trigger('click');
    await flushPromises();

    expect(subjectTitle(wrapper).text()).toContain('Modified subject');
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

    await editSubject(wrapper, 'Changed subject');
    await wrapper
      .find('[data-testid="kanban-opportunity-cancel"]')
      .trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('emits removeCard with the loaded card from the header delete action', async () => {
    const card = buildCard();
    const wrapper = await mountModal({ card });

    await openHeaderMenu(wrapper);
    await headerMenuItem(wrapper, 'Remove').trigger('click');

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

  it('renders the status affordance with a border and chevron', async () => {
    const wrapper = await mountModal({
      card: buildCard({ kanbanStageId: 15 }),
      wonStageId: 20,
      lostStageId: 30,
      stages: [{ id: 15, name: 'Prospecting' }],
    });
    const badge = wrapper.find('[data-testid="kanban-card-status-badge"]');

    expect(badge.classes()).toContain('border');
    expect(badge.find('.i-lucide-chevron-down').exists()).toBe(true);
  });

  it('shows a terminal reason only beside a terminal status', async () => {
    const reasons = [{ id: 9, title: 'Budget approved', reason_type: 'won' }];
    const terminalWrapper = await mountModal({
      card: buildCard({ kanbanStageId: 20, kanbanReasonId: 9 }),
      wonStageId: 20,
      lostStageId: 30,
      reasons,
      stages: [{ id: 20, name: 'Won' }],
    });
    expect(
      terminalWrapper.find('[data-testid="kanban-opportunity-reason"]').text()
    ).toContain('Reason: Budget approved');

    const openWrapper = await mountModal({
      card: buildCard({ kanbanStageId: 15, kanbanReasonId: 9 }),
      wonStageId: 20,
      lostStageId: 30,
      reasons,
      stages: [{ id: 15, name: 'Prospecting' }],
    });
    expect(
      openWrapper.find('[data-testid="kanban-opportunity-reason"]').exists()
    ).toBe(false);
  });

  it('renders stage time and a stale SLA class in the quick controls', async () => {
    const stageEnteredAt = new Date(
      Date.now() - 2 * 24 * 60 * 60 * 1000
    ).toISOString();
    const wrapper = await mountModal({
      card: buildCard({ kanbanStageId: 15, stageEnteredAt }),
      stages: [{ id: 15, name: 'Prospecting', slaHours: 1 }],
    });
    const sla = wrapper.find('[data-testid="kanban-opportunity-stage-sla"]');

    expect(sla.exists()).toBe(true);
    expect(sla.classes()).toContain('text-n-ruby-11');
  });

  it('opens Products from a non-zero value chip and hides zero value', async () => {
    const wrapper = await mountModal({ card: buildCard({ value: 4800 }) });
    const valueButton = wrapper.find(
      '[data-testid="kanban-opportunity-total-value"]'
    );

    expect(valueButton.exists()).toBe(true);
    await valueButton.trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-products-tab"]').exists()
    ).toBe(true);

    const zeroWrapper = await mountModal({ card: buildCard({ value: 0 }) });
    expect(
      zeroWrapper
        .find('[data-testid="kanban-opportunity-total-value"]')
        .exists()
    ).toBe(false);
  });

  it('caps long labels at three chips and a remaining count', async () => {
    const manyLabels = Array.from({ length: 8 }, (_, index) => ({
      id: index + 1,
      title: `long-label-${index + 1}`,
      color: '#ff0000',
    }));
    const wrapper = await mountModal({
      accountLabels: manyLabels,
      assignedLabels: manyLabels,
    });

    expect(labelButtons(wrapper)).toHaveLength(3);
    expect(
      wrapper.find('[data-testid="kanban-opportunity-more-labels"]').text()
    ).toBe('+5');
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
    await descriptionInput(wrapper).setValue('Edited description');

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
    expect(descriptionInput(wrapper).element.value).toBe('Edited description');
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

    await descriptionInput(wrapper).setValue('Updated description');
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

  it('moves the card to another stage through the header move button', async () => {
    const moveToStage = vi.fn().mockResolvedValue(true);
    const wrapper = await mountModal({
      board: { id: 10, name: 'Sales', customFields: [] },
      card: buildCard({ kanbanStageId: 15 }),
      stages: [
        { id: 15, name: 'Prospecting' },
        { id: 16, name: 'Negotiation' },
      ],
      moveToStage,
    });

    await openMoveDialogFromHeader(wrapper);
    await submitMoveToStage(wrapper, 1);

    expect(moveToStage).toHaveBeenCalledWith(
      expect.objectContaining({ id: 501 }),
      16
    );
    expect(
      wrapper.find('[data-testid="kanban-card-move-dialog"]').exists()
    ).toBe(false);
  });

  it('keeps the current stage when the move is rejected', async () => {
    const moveToStage = vi.fn().mockResolvedValue(false);
    const wrapper = await mountModal({
      board: { id: 10, name: 'Sales', customFields: [] },
      card: buildCard({ kanbanStageId: 15 }),
      stages: [
        { id: 15, name: 'Prospecting' },
        { id: 16, name: 'Negotiation' },
      ],
      moveToStage,
    });

    await openMoveDialogFromHeader(wrapper);
    await submitMoveToStage(wrapper, 1);

    expect(
      wrapper.find('[data-testid="kanban-opportunity-move-to"]').text()
    ).toContain('Prospecting');
  });

  it('opens the shared move dialog with the current stage at the top', async () => {
    const board = { id: 10, name: 'Sales', customFields: [] };
    const moveToStage = vi.fn().mockResolvedValue(true);
    const wrapper = await mountModal({
      board,
      boards: [board],
      moveToStage,
      card: buildCard({ kanbanStageId: 15 }),
      stages: [
        { id: 15, name: 'Prospecting' },
        { id: 16, name: 'Negotiation' },
        { id: 20, name: 'Won' },
        { id: 30, name: 'Lost' },
      ],
      wonStageId: 20,
      lostStageId: 30,
    });

    await openMoveDialogFromHeader(wrapper);

    const stages = wrapper.findAll(
      '[data-testid="kanban-card-move-dialog-stage"]'
    );
    expect(stages).toHaveLength(2);
    expect(stages[0].text()).toContain('Prospecting (current) — move to top');

    await stages[0].trigger('click');
    await wrapper
      .find('[data-testid="kanban-card-move-dialog-submit"]')
      .trigger('click');
    await flushPromises();

    expect(moveToStage).toHaveBeenCalledWith(
      expect.objectContaining({ id: 501 }),
      15
    );
    expect(wrapper.emitted('updated')).toBeTruthy();
    expect(
      wrapper.find('[data-testid="kanban-card-move-dialog"]').exists()
    ).toBe(false);
  });

  it('shows shared move consequences and moves across funnels', async () => {
    const sourceBoard = {
      id: 10,
      name: 'Sales',
      wonStageId: 20,
      lostStageId: 30,
      customFields: [
        { key: 'segment', fieldType: 'text', multiple: false },
        { key: 'region', fieldType: 'text', multiple: false },
        { key: 'products', fieldType: 'list', multiple: true },
      ],
    };
    const targetBoard = {
      id: 11,
      name: 'Support',
      stagesSummary: [{ id: 40, name: 'Triage' }],
      customFields: [{ key: 'segment', fieldType: 'text', multiple: false }],
    };
    KanbanBoardsAPI.moveCardToBoard.mockResolvedValue({});
    const wrapper = await mountModal({
      board: sourceBoard,
      boards: [sourceBoard, targetBoard],
      card: buildCard({
        kanbanStageId: 30,
        kanbanReasonId: 9,
        customFieldKeys: ['segment', 'region', 'products'],
      }),
      stages: [{ id: 30, name: 'Lost' }],
      wonStageId: 20,
      lostStageId: 30,
      reasons: [{ id: 9, title: 'Budget rejected' }],
    });

    await openMoveDialogFromHeader(wrapper);
    const boardSelect = wrapper
      .findAllComponents({ name: 'Select' })
      .find(select =>
        select.props('options').some(option => option.value === 11)
      );
    await boardSelect.vm.$emit('update:modelValue', 11);
    await wrapper
      .find('[data-testid="kanban-card-move-dialog-stage"]')
      .trigger('click');

    expect(
      wrapper
        .find('[data-testid="kanban-card-move-dialog-consequences"]')
        .text()
    ).toContain('The opportunity will be reopened.');
    expect(wrapper.text()).toContain(
      'The reason "Budget rejected" will be removed.'
    );
    expect(wrapper.text()).toContain('2 of 3 custom fields');

    await wrapper
      .find('[data-testid="kanban-card-move-dialog-submit"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.moveCardToBoard).toHaveBeenCalledWith(10, 501, {
      target_kanban_board_id: 11,
      kanban_stage_id: 40,
    });
    expect(wrapper.emitted('boardChanged')).toEqual([
      [{ boardId: 11, boardName: 'Support' }],
    ]);
  });

  it('hides conversation navigation and inbox context when opened from conversation', async () => {
    const wrapper = await mountModal({ openedFromConversation: true });

    await openHeaderMenu(wrapper);
    expect(headerMenuItem(wrapper, 'Open conversation')).toBeUndefined();
    expect(headerMenuItem(wrapper, 'Open in a new tab')).toBeUndefined();
    expect(headerMenuItem(wrapper, 'Open in funnel')).toBeTruthy();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-subtitle"]').text()
    ).not.toContain('Sales Inbox');
  });
});
