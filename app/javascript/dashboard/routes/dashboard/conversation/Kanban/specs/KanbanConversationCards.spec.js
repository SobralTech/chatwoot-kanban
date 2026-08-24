import { mount, flushPromises } from '@vue/test-utils';
import { computed, nextTick } from 'vue';

import KanbanConversationCards from '../KanbanConversationCards.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const translations = {
  'CONVERSATION_SIDEBAR.KANBAN.LOADING': 'Loading opportunities',
  'CONVERSATION_SIDEBAR.KANBAN.EMPTY': 'No opportunities linked',
  'CONVERSATION_SIDEBAR.KANBAN.ERROR': 'Failed to load opportunities',
  'CONVERSATION_SIDEBAR.KANBAN.NEW_OPPORTUNITY': 'New opportunity',
  'CONVERSATION_SIDEBAR.KANBAN.BOARD': 'Funnel',
  'CONVERSATION_SIDEBAR.KANBAN.SUBJECT': 'Subject',
  'CONVERSATION_SIDEBAR.KANBAN.STAGE': 'Stage',
  'CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD': 'Select a funnel',
  'CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE': 'Select a stage',
  'CONVERSATION_SIDEBAR.KANBAN.NO_ELIGIBLE_BOARDS':
    'No funnel accepts this inbox.',
  'CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD':
    'This conversation already has #{id} here',
  'CONVERSATION_SIDEBAR.KANBAN.OPEN_EXISTING': 'Open existing',
  'CONVERSATION_SIDEBAR.KANBAN.CREATE_ERROR': 'Failed to create opportunity',
  'CONVERSATION_SIDEBAR.KANBAN.CREATED': 'Opportunity created',
  'CONVERSATION_SIDEBAR.KANBAN.OPEN_DETAILS': 'Open details',
  'CONVERSATION_SIDEBAR.KANBAN.CANCEL': 'Cancel',
  'CONVERSATION_SIDEBAR.KANBAN.CREATE': 'Create',
  'CONVERSATION_SIDEBAR.KANBAN.CREATE_IN_ANOTHER_BOARD':
    'Create in another funnel',
  'CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_TITLE': 'Delete opportunity',
  'CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_DESCRIPTION':
    'This cannot be undone.',
  'CONVERSATION_SIDEBAR.KANBAN.DELETE_CONFIRM_BUTTON': 'Yes, delete',
  'KANBAN.CARD.MOVE_BOARD_SUCCESS': 'Opportunity moved to {board}.',
  'CONVERSATION.PRIORITY.OPTIONS.NONE': 'No priority',
  'CONVERSATION.PRIORITY.OPTIONS.URGENT': 'Urgent',
  'CONVERSATION.PRIORITY.OPTIONS.HIGH': 'High',
  'CONVERSATION.PRIORITY.OPTIONS.MEDIUM': 'Medium',
  'CONVERSATION.PRIORITY.OPTIONS.LOW': 'Low',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      Object.entries(values).reduce(
        (message, [name, value]) =>
          message.replaceAll(`{${name}}`, String(value)),
        translations[key] || key
      ),
  }),
}));

const routerPush = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: routerPush }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    getConversationCards: vi.fn(),
    getBoards: vi.fn(),
    createConversationCard: vi.fn(),
    updateCardById: vi.fn(),
    reopenCardById: vi.fn(),
    updateCardDetailsById: vi.fn(),
    updateCardLabels: vi.fn(),
    getCardAssignees: vi.fn(),
    updateCardAssignees: vi.fn(),
    reorderCardById: vi.fn(),
    moveCardToBoard: vi.fn(),
    deleteCardById: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: vi.fn(),
  useMapGetter: vi.fn(),
}));

vi.mock('dashboard/composables/useSlaClock', () => ({
  useSlaClock: () => ({ value: Date.now() }),
}));

const currentChat = {
  id: 456,
  inbox_id: 5,
  meta: {
    sender: {
      id: 12,
      name: 'Maria Silva',
    },
  },
};

const store = {
  getters: {
    'inboxes/getInboxById': vi.fn(() => ({ id: 5, name: 'Sales Inbox' })),
  },
};

const buildStage = (id, name) => ({
  id,
  name,
  color: '#2781F6',
  active: true,
});

const buildBoard = overrides => ({
  id: 10,
  name: 'Sales',
  active: true,
  inbox_scope_mode: 'selected_inboxes',
  allowed_inboxes: [{ id: 5, name: 'Sales Inbox' }],
  won_stage_id: 22,
  lost_stage_id: 23,
  lost_reason_required: true,
  stages_summary: [
    buildStage(20, 'New'),
    buildStage(21, 'Qualified'),
    buildStage(22, 'Won'),
    buildStage(23, 'Lost'),
  ],
  reasons: [{ id: 7, title: 'Budget' }],
  ...overrides,
});

const buildCard = overrides => ({
  id: 123,
  origin: 'conversation',
  subject: 'Maria Silva - Sales Inbox',
  value: '125.50',
  priority: 'high',
  due_at: null,
  stage_entered_at: '2026-06-07T18:00:00-03:00',
  kanban_board: { id: 10, name: 'Sales' },
  kanban_stage: { id: 20, name: 'New', color: '#2781F6', sla_hours: 24 },
  conversation_id: 456,
  labels: [],
  assignees: [],
  ...overrides,
});

const cardItemStub = {
  name: 'KanbanConversationCardItem',
  props: [
    'card',
    'board',
    'regularStages',
    'assignableUsers',
    'isAssigneesLoading',
    'isBusy',
    'isHighlighted',
  ],
  emits: [
    'changeStatus',
    'delete',
    'loadAssignees',
    'openDetails',
    'openMove',
    'updateAssignees',
    'updateDueDate',
    'updateLabels',
    'updatePriority',
    'updateStage',
  ],
  template: `
    <article data-testid="kanban-conversation-card">
      <span v-if="Number(card.value)" data-testid="card-value">{{ card.value }}</span>
      <span data-testid="card-priority-value">{{ card.priority }}</span>
      <button type="button" data-testid="card-subject" @click="$emit('openDetails', card)">
        {{ card.subject }}
      </button>
      <button type="button" data-testid="card-board" @click="$emit('openMove', card)">
        board
      </button>
      <button type="button" data-testid="card-priority" @click="$emit('updatePriority', card, 'urgent')">
        priority
      </button>
      <button type="button" data-testid="card-stage" @click="$emit('updateStage', card, 21)">
        stage
      </button>
    </article>
  `,
};

const dialogStub = {
  name: 'Dialog',
  template: '<div />',
};

const moveDialogStub = {
  name: 'KanbanCardMoveDialog',
  props: ['card', 'existingCards', 'boards', 'isMoving'],
  emits: ['close', 'move'],
  template: `
    <div data-testid="kanban-card-move-dialog">
      <button
        type="button"
        data-testid="move-card"
        @click="$emit('move', { boardId: 11, stageId: 30 })"
      >
        move
      </button>
    </div>
  `,
};

const opportunityPanelStub = {
  name: 'KanbanOpportunityPanel',
  props: {
    boardId: [Number, String],
    cardId: [Number, String],
    board: Object,
    boards: Array,
    stages: Array,
    openedFromConversation: Boolean,
  },
  emits: ['close'],
  template: '<div data-testid="kanban-conversation-opportunity-panel" />',
};

let wrapper;

const mountComponent = (props = { conversationId: 456 }) => {
  wrapper = mount(KanbanConversationCards, {
    props,
    global: {
      stubs: {
        KanbanConversationCardItem: cardItemStub,
        KanbanCardMoveDialog: moveDialogStub,
        KanbanOpportunityPanel: opportunityPanelStub,
        Dialog: dialogStub,
      },
    },
  });

  return wrapper;
};

const openCreateForm = async mountedWrapper => {
  const emptyButton = mountedWrapper.find(
    '[data-testid="kanban-conversation-card-create-empty"]'
  );
  const createButton = emptyButton.exists()
    ? emptyButton
    : mountedWrapper.get(
        '[data-testid="kanban-conversation-card-create-another"]'
      );
  await createButton.trigger('click');
  await flushPromises();
};

describe('KanbanConversationCards', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    emitter.all.clear();

    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(key => {
      if (key === 'getSelectedChat') return computed(() => currentChat);
      if (key === 'labels/getLabels') return computed(() => []);
      return computed(() => undefined);
    });

    KanbanBoardsAPI.getBoards.mockResolvedValue({
      data: [buildBoard(), buildBoard({ id: 11, name: 'Renewals' })],
    });
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [] },
    });
    KanbanBoardsAPI.createConversationCard.mockResolvedValue({
      data: { payload: buildCard() },
    });
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: { priority: 'urgent' },
    });
    KanbanBoardsAPI.reorderCardById.mockResolvedValue({});
    KanbanBoardsAPI.updateCardById.mockResolvedValue({});
    KanbanBoardsAPI.reopenCardById.mockResolvedValue({});
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: [] },
    });
    KanbanBoardsAPI.getCardAssignees.mockResolvedValue({
      data: { payload: [], assignable_users: [] },
    });
    KanbanBoardsAPI.updateCardAssignees.mockResolvedValue({
      data: { payload: [], assignable_users: [] },
    });
    KanbanBoardsAPI.moveCardToBoard.mockResolvedValue({});
    KanbanBoardsAPI.deleteCardById.mockResolvedValue({});
  });

  afterEach(() => {
    wrapper?.unmount();
    emitter.all.clear();
  });

  it('loads boards once and conversation cards on mount', async () => {
    mountComponent();
    await flushPromises();

    expect(KanbanBoardsAPI.getBoards).toHaveBeenCalledTimes(1);
    expect(KanbanBoardsAPI.getBoards).toHaveBeenCalledWith({
      signal: expect.any(AbortSignal),
    });
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledWith(456, {
      signal: expect.any(AbortSignal),
    });
  });

  it('renders the read-only card list without the old edit form', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();

    expect(
      mountedWrapper.find('[data-testid="card-subject"]').text()
    ).toContain('Maria Silva');
    expect(mountedWrapper.find('[data-testid="card-value"]').text()).toBe(
      '125.50'
    );
    expect(
      mountedWrapper
        .find('[data-testid="kanban-conversation-card-form"]')
        .exists()
    ).toBe(false);
    expect(mountedWrapper.text()).not.toContain('Saving');
  });

  it('updates only priority through the card details endpoint', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-priority"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      123,
      { priority: 'urgent' }
    );
  });

  it('reverts a failed priority update and shows translated feedback', async () => {
    let rejectUpdate;
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    KanbanBoardsAPI.updateCardDetailsById.mockReturnValue(
      new Promise((resolve, reject) => {
        rejectUpdate = reject;
      })
    );

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-priority"]').trigger('click');
    await nextTick();
    expect(
      mountedWrapper.get('[data-testid="card-priority-value"]').text()
    ).toBe('urgent');

    rejectUpdate(new Error('failed'));
    await flushPromises();
    expect(
      mountedWrapper.get('[data-testid="card-priority-value"]').text()
    ).toBe('high');
    expect(useAlert).toHaveBeenCalled();
  });

  it('reorders a card to a regular stage with no position change', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-stage"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 123, {
      card: { kanban_stage_id: 21, after_card_id: null },
    });
  });

  it('reloads after a matching realtime event', async () => {
    mountComponent();
    await flushPromises();

    emitter.emit(BUS_EVENTS.KANBAN_REALTIME_EVENT, {
      event: 'kanban.card.updated',
      data: { conversation_id: 456, card_id: 123 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
  });

  it('waits for a busy card action before applying a realtime refresh', async () => {
    let resolveUpdate;
    KanbanBoardsAPI.updateCardDetailsById.mockReturnValue(
      new Promise(resolve => {
        resolveUpdate = resolve;
      })
    );
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-priority"]').trigger('click');

    emitter.emit(BUS_EVENTS.KANBAN_REALTIME_EVENT, {
      event: 'kanban.card.updated',
      data: { conversation_id: 456, card_id: 123 },
    });
    await flushPromises();
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(1);

    resolveUpdate({ data: { priority: 'urgent' } });
    await flushPromises();
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
  });

  it('creates a card with only board, stage, and subject', async () => {
    const mountedWrapper = mountComponent();
    await flushPromises();
    await openCreateForm(mountedWrapper);

    const boardSelect = mountedWrapper.get(
      '[data-testid="kanban-conversation-card-board"]'
    );
    expect(boardSelect.element.value).toBe('');

    await boardSelect.setValue('10');
    await mountedWrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .setValue('20');
    await mountedWrapper
      .get('[data-testid="kanban-conversation-card-form"]')
      .trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledWith(
      456,
      {
        card: {
          kanban_board_id: 10,
          kanban_stage_id: 20,
          subject: 'Maria Silva - Sales Inbox',
        },
      },
      { signal: expect.any(AbortSignal) }
    );
  });

  it('preselects the only eligible funnel and excludes terminal stages', async () => {
    KanbanBoardsAPI.getBoards.mockResolvedValue({
      data: [buildBoard()],
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await openCreateForm(mountedWrapper);

    expect(
      mountedWrapper.get('[data-testid="kanban-conversation-card-board"]')
        .element.value
    ).toBe('10');
    const stageOptions = mountedWrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .findAll('option')
      .map(option => option.element.value);
    expect(stageOptions.filter(Boolean)).toEqual(['20', '21']);
  });

  it('shows the duplicate warning and emits the existing card', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await openCreateForm(mountedWrapper);
    await mountedWrapper
      .get('[data-testid="kanban-conversation-card-board"]')
      .setValue('10');

    expect(
      mountedWrapper
        .find('[data-testid="kanban-conversation-card-duplicate-warning"]')
        .exists()
    ).toBe(true);
    await mountedWrapper
      .get('[data-testid="kanban-conversation-card-duplicate-warning"] button')
      .trigger('click');

    expect(mountedWrapper.emitted('open-existing')?.[0][0].id).toBe(123);
  });

  it('opens the shared opportunity panel from the subject', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-subject"]').trigger('click');

    const panel = mountedWrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    expect(panel.exists()).toBe(true);
    expect(panel.props('openedFromConversation')).toBe(true);
    expect(panel.props('cardId')).toBe(123);
  });

  it('opens the move dialog from the funnel name and moves the card', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-board"]').trigger('click');
    await mountedWrapper.get('[data-testid="move-card"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.moveCardToBoard).toHaveBeenCalledWith(10, 123, {
      target_kanban_board_id: 11,
      kanban_stage_id: 30,
    });
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith('Opportunity moved to Renewals.');
  });

  it('navigates to the funnel and closes the panel on openFunnel', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const mountedWrapper = mountComponent();
    await flushPromises();
    await mountedWrapper.get('[data-testid="card-subject"]').trigger('click');

    const panel = mountedWrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    // The panel hands back the card it loaded, already camelized.
    panel.vm.$emit('openFunnel', { id: 123, kanbanBoardId: 10 });
    await nextTick();

    expect(routerPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 10 },
      query: { card_id: 123 },
    });
    expect(
      mountedWrapper.findComponent({ name: 'KanbanOpportunityPanel' }).exists()
    ).toBe(false);
  });
});
