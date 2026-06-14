import { mount, flushPromises } from '@vue/test-utils';
import { computed, nextTick } from 'vue';
import KanbanConversationCards from '../KanbanConversationCards.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { messageStamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('shared/helpers/timeHelper', () => ({
  messageStamp: vi.fn(() => 'Jun 7, 2026 6:00 PM'),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => {
      const translations = {
        'CONVERSATION_SIDEBAR.KANBAN.LOADING': 'Loading opportunities',
        'CONVERSATION_SIDEBAR.KANBAN.EMPTY':
          'No opportunities linked to this conversation',
        'CONVERSATION_SIDEBAR.KANBAN.ERROR': 'Failed to load opportunities',
        'CONVERSATION_SIDEBAR.KANBAN.ADD': 'Add to Kanban',
        'CONVERSATION_SIDEBAR.KANBAN.CREATE_TITLE': 'Create opportunity',
        'CONVERSATION_SIDEBAR.KANBAN.BOARD': 'Board',
        'CONVERSATION_SIDEBAR.KANBAN.SUBJECT': 'Subject',
        'CONVERSATION_SIDEBAR.KANBAN.STAGE': 'Opportunity stage',
        'CONVERSATION_SIDEBAR.KANBAN.DUE_DATE': 'Due date',
        'CONVERSATION_SIDEBAR.KANBAN.LABELS': 'Labels',
        'CONVERSATION_SIDEBAR.KANBAN.NOT_SET': 'Not set',
        'CONVERSATION_SIDEBAR.KANBAN.NO_LABELS': 'No labels',
        'CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD': 'Select a board',
        'CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE': 'Select a stage',
        'CONVERSATION_SIDEBAR.KANBAN.EMPTY_BOARDS':
          'No active boards available',
        'CONVERSATION_SIDEBAR.KANBAN.EMPTY_STAGES':
          'No active stages available',
        'CONVERSATION_SIDEBAR.KANBAN.CREATE_ERROR':
          'Failed to create opportunity',
        'CONVERSATION_SIDEBAR.KANBAN.CREATED': 'Opportunity created',
        'CONVERSATION_SIDEBAR.KANBAN.CANCEL': 'Cancel',
        'CONVERSATION_SIDEBAR.KANBAN.CREATE': 'Create',
        'CONVERSATION_SIDEBAR.KANBAN.SAVE': 'Save',
        'CONVERSATION_SIDEBAR.KANBAN.SAVING': 'Saving...',
        'CONVERSATION_SIDEBAR.KANBAN.UPDATE_ERROR':
          'Failed to update opportunity',
        'CONVERSATION_SIDEBAR.KANBAN.UPDATED': 'Opportunity updated',
      };

      return translations[key] || key;
    },
  }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    getConversationCards: vi.fn(),
    getBoards: vi.fn(),
    showBoard: vi.fn(),
    createConversationCard: vi.fn(),
    updateCardDetailsById: vi.fn(),
    updateCardLabels: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: vi.fn(),
  useMapGetter: vi.fn(),
}));

vi.mock('shared/components/ui/label/LabelDropdown.vue', () => ({
  default: {
    name: 'LabelDropdown',
    props: {
      accountLabels: { type: Array, default: () => [] },
      selectedLabels: { type: Array, default: () => [] },
      allowCreation: { type: Boolean, default: false },
    },
    emits: ['add', 'remove'],
    template: `
      <div data-testid="label-dropdown">
        <button
          type="button"
          data-testid="add-label"
          @click="$emit('add', accountLabels[0])"
        >
          add label
        </button>
        <button
          type="button"
          data-testid="remove-label"
          @click="$emit('remove', selectedLabels[0])"
        >
          remove label
        </button>
      </div>
    `,
  },
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

const accountLabels = [
  { id: 1, title: 'urgente', color: '#ff0000' },
  { id: 2, title: 'vendas', color: '#00ff00' },
];

const buildCard = overrides => ({
  id: 123,
  origin: 'conversation',
  subject: 'Maria Silva - Sales Inbox',
  kanban_board: {
    id: 10,
    name: 'Sales',
  },
  kanban_stage: {
    id: 20,
    name: 'New',
    color: 'blue',
  },
  due_at: '2026-06-07T18:00:00-03:00',
  labels: [
    { id: 1, title: 'urgente', color: '#ff0000', description: null },
    { id: 2, title: 'vendas', color: '#00ff00', description: 'Sales label' },
  ],
  conversation_id: 456,
  ...overrides,
});

const buildBoard = overrides => ({
  id: 10,
  name: 'Sales',
  active: true,
  ...overrides,
});

const buildStage = overrides => ({
  id: 20,
  name: 'New',
  active: true,
  ...overrides,
});

const store = {
  dispatch: vi.fn(),
  getters: {
    'inboxes/getInboxById': vi.fn(() => ({ id: 5, name: 'Sales Inbox' })),
  },
};

const mountComponent = (props = { conversationId: 456 }) =>
  mount(KanbanConversationCards, {
    props,
  });

const openForm = async wrapper => {
  await wrapper.find('button').trigger('click');
  await flushPromises();
};

const openEditForm = async () => {
  await flushPromises();
};

const findButtonByText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text() === text);

const emitKanbanRealtimeEvent = payload => {
  emitter.emit(BUS_EVENTS.KANBAN_REALTIME_EVENT, payload);
};

const formLabels = wrapper =>
  wrapper
    .findAll('label span')
    .map(node => node.text())
    .filter(Boolean);

describe('KanbanConversationCards', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    emitter.all.clear();
    messageStamp.mockReturnValue('Jun 7, 2026 6:00 PM');

    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(key => {
      if (key === 'getSelectedChat') return computed(() => currentChat);
      if (key === 'labels/getLabels') return computed(() => accountLabels);
      return computed(() => undefined);
    });

    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [] },
    });
    KanbanBoardsAPI.getBoards.mockResolvedValue({
      data: [
        buildBoard(),
        buildBoard({ id: 11, name: 'Inactive', active: false }),
      ],
    });
    KanbanBoardsAPI.showBoard.mockResolvedValue({
      data: {
        stages: [
          buildStage(),
          buildStage({ id: 21, name: 'Inactive', active: false }),
        ],
      },
    });
    KanbanBoardsAPI.createConversationCard.mockResolvedValue({
      data: { payload: buildCard() },
    });
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ subject: 'Updated opportunity' }),
    });
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: [accountLabels[1]] },
    });
  });

  afterEach(() => {
    emitter.all.clear();
  });

  it('loads cards for conversationId', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    mountComponent();
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledWith(456, {
      signal: expect.any(AbortSignal),
    });
  });

  it('reloads when conversationId changes', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.setProps({ conversationId: 789 });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledWith(789, {
      signal: expect.any(AbortSignal),
    });
  });

  it('ignores stale responses', async () => {
    const resolvers = [];
    KanbanBoardsAPI.getConversationCards.mockImplementation(
      () =>
        new Promise(resolve => {
          resolvers.push(resolve);
        })
    );

    const wrapper = mountComponent();
    await wrapper.setProps({ conversationId: 789 });

    resolvers[1]({ data: { payload: [buildCard({ subject: 'Fresh card' })] } });
    await flushPromises();
    resolvers[0]({ data: { payload: [buildCard({ subject: 'Stale card' })] } });
    await flushPromises();

    expect(wrapper.find('input[type="text"]').element.value).toBe('Fresh card');
    expect(wrapper.text()).not.toContain('Stale card');
  });

  it('aborts stale requests when conversationId changes', async () => {
    const signals = [];
    KanbanBoardsAPI.getConversationCards.mockImplementation((_, config) => {
      signals.push(config.signal);
      return new Promise(() => {});
    });

    const wrapper = mountComponent();
    await wrapper.setProps({ conversationId: 789 });

    expect(signals[0].aborted).toBe(true);
  });

  it('renders loading state', async () => {
    KanbanBoardsAPI.getConversationCards.mockImplementation(
      () => new Promise(() => {})
    );

    const wrapper = mountComponent();
    await nextTick();

    expect(wrapper.text()).toContain('Loading opportunities');
  });

  it('renders empty state', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'No opportunities linked to this conversation'
    );
  });

  it('renders error state', async () => {
    KanbanBoardsAPI.getConversationCards.mockRejectedValue(new Error('Failed'));

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Failed to load opportunities');
  });

  it('registers and removes the kanban realtime listener', async () => {
    const onSpy = vi.spyOn(emitter, 'on');
    const offSpy = vi.spyOn(emitter, 'off');

    const wrapper = mountComponent();
    await flushPromises();
    const registeredHandler = onSpy.mock.calls.find(
      ([eventName]) => eventName === BUS_EVENTS.KANBAN_REALTIME_EVENT
    )?.[1];

    expect(registeredHandler).toEqual(expect.any(Function));

    wrapper.unmount();

    expect(offSpy).toHaveBeenCalledWith(
      BUS_EVENTS.KANBAN_REALTIME_EVENT,
      registeredHandler
    );
  });

  it('refreshes cards after a relevant kanban realtime event', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { card_id: 123, conversation_id: 456 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenLastCalledWith(456, {
      signal: expect.any(AbortSignal),
    });

    wrapper.unmount();
  });

  it.each([
    ['kanban.card.created'],
    ['kanban.card.updated'],
    ['kanban.card.deleted'],
    ['kanban.card.reordered'],
  ])('refreshes cards for compact %s events', async event => {
    const wrapper = mountComponent();
    await flushPromises();

    emitKanbanRealtimeEvent({
      event,
      data: { board_id: 10, stage_id: 20, card_id: 123 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);

    wrapper.unmount();
  });

  it('does not refresh for clearly unrelated kanban realtime events', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { card_id: 999, conversation_id: 789 },
    });
    emitKanbanRealtimeEvent({
      event: 'kanban.stage.updated',
      data: { board_id: 10, stage_id: 20 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(1);

    wrapper.unmount();
  });

  it('avoids duplicate concurrent realtime fetches', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValueOnce({
      data: { payload: [] },
    });
    const resolvers = [];
    KanbanBoardsAPI.getConversationCards.mockImplementation(
      () =>
        new Promise(resolve => {
          resolvers.push(resolve);
        })
    );
    const wrapper = mountComponent();
    await flushPromises();

    emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { card_id: 123, conversation_id: 456 },
    });
    emitKanbanRealtimeEvent({
      event: 'kanban.card.deleted',
      data: { card_id: 123, conversation_id: 456 },
    });
    await nextTick();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);

    resolvers[0]({ data: { payload: [buildCard({ subject: 'Fresh card' })] } });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);

    expect(wrapper.find('input[type="text"]').element.value).toBe('Fresh card');
  });

  it('renders editable card fields in the requested order', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const wrapper = mountComponent();
    await flushPromises();

    const editLabels = wrapper
      .findAll('li form > div p.text-xs, li form > label > span.text-xs')
      .map(node => node.text());

    expect(editLabels).toEqual([
      'Board',
      'Subject',
      'Opportunity stage',
      'Due date',
      'Labels',
    ]);
  });

  it('renders linked card metadata in editable fields', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Maria Silva - Sales Inbox'
    );
    expect(wrapper.text()).toContain('New');
    expect(wrapper.find('select').element.value).toBe('20');
    expect(wrapper.find('input[type="datetime-local"]').element.value).toBe(
      '2026-06-07T21:00'
    );
    expect(wrapper.text()).toContain('urgente');
    expect(wrapper.text()).toContain('vendas');
  });

  it('opens linked cards in edit mode for unexpected stage colors', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: {
        payload: [
          buildCard({ kanban_stage: { id: 20, name: 'New', color: 'legacy' } }),
        ],
      },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Maria Silva - Sales Inbox'
    );
  });

  it('renders empty due date and labels in editable fields', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard({ due_at: null, labels: [] })] },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('input[type="datetime-local"]').element.value).toBe('');
    expect(wrapper.findAll('.rounded-md.bg-n-slate-3')).toHaveLength(0);
  });

  it('opens the creation form from the Add to Kanban button', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await openForm(wrapper);

    expect(wrapper.text()).toContain('Create opportunity');
    expect(store.dispatch).toHaveBeenCalledWith('labels/get');
  });

  it('preserves the creation form during realtime refresh and refreshes after cancel', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);
    await wrapper.find('input[type="text"]').setValue('Draft opportunity');

    emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { card_id: 123, conversation_id: 456 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(1);
    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Draft opportunity'
    );

    await findButtonByText(wrapper, 'Cancel').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
  });

  it('renders fields in the requested order', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await openForm(wrapper);

    expect(formLabels(wrapper)).toEqual([
      'Board',
      'Subject',
      'Opportunity stage',
      'Due date',
      'Labels',
    ]);
  });

  it('loads active boards when opening the form and selects the first board', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await openForm(wrapper);

    expect(KanbanBoardsAPI.getBoards).toHaveBeenCalledWith({
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.find('select').element.value).toBe('10');
    expect(wrapper.text()).not.toContain('Inactive');
  });

  it('loads active stages after board selection and selects the first stage', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await openForm(wrapper);

    expect(KanbanBoardsAPI.showBoard).toHaveBeenCalledWith(10, {
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.findAll('select')[1].element.value).toBe('20');
  });

  it('clears the previous stage when board changes', async () => {
    KanbanBoardsAPI.getBoards.mockResolvedValue({
      data: [buildBoard(), buildBoard({ id: 11, name: 'Support' })],
    });
    KanbanBoardsAPI.showBoard
      .mockResolvedValueOnce({ data: { stages: [buildStage()] } })
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            setTimeout(
              () => resolve({ data: { stages: [buildStage({ id: 30 })] } }),
              0
            );
          })
      );
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('select').setValue('11');

    expect(wrapper.findAll('select')[1].element.value).toBe('');
  });

  it('prefills the subject and keeps it editable', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await openForm(wrapper);
    const input = wrapper.find('input[type="text"]');
    expect(input.element.value).toBe('Maria Silva - Sales Inbox');

    await input.setValue('Custom opportunity');
    expect(input.element.value).toBe('Custom opportunity');
  });

  it('submits null when due date is empty', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('form').trigger('submit.prevent');

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledWith(
      456,
      expect.objectContaining({
        card: expect.objectContaining({ due_at: null }),
      }),
      { signal: expect.any(AbortSignal) }
    );
  });

  it('submits ISO8601 when due date is filled', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper
      .find('input[type="datetime-local"]')
      .setValue('2026-06-07T18:00');
    await wrapper.find('form').trigger('submit.prevent');

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledWith(
      456,
      expect.objectContaining({
        card: expect.objectContaining({
          due_at: new Date('2026-06-07T18:00').toISOString(),
        }),
      }),
      { signal: expect.any(AbortSignal) }
    );
  });

  it('reuses the existing label selector and allows multiple labels', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    const labelDropdown = wrapper.findComponent({ name: 'LabelDropdown' });
    expect(labelDropdown.props('allowCreation')).toBe(false);

    await labelDropdown.vm.$emit('add', accountLabels[0]);
    await labelDropdown.vm.$emit('add', accountLabels[1]);
    await wrapper.find('form').trigger('submit.prevent');

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledWith(
      456,
      expect.objectContaining({
        card: expect.objectContaining({ labels: ['urgente', 'vendas'] }),
      }),
      { signal: expect.any(AbortSignal) }
    );
  });

  it('submits board, subject, stage, due_at, and labels', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('input[type="text"]').setValue('  Enterprise renewal  ');
    await wrapper
      .findComponent({ name: 'LabelDropdown' })
      .vm.$emit('add', accountLabels[0]);
    await wrapper.find('form').trigger('submit.prevent');

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledWith(
      456,
      {
        card: {
          kanban_board_id: 10,
          kanban_stage_id: 20,
          subject: 'Enterprise renewal',
          due_at: null,
          labels: ['urgente'],
        },
      },
      { signal: expect.any(AbortSignal) }
    );
  });

  it('blocks duplicate submit while pending', async () => {
    KanbanBoardsAPI.createConversationCard.mockImplementation(
      () => new Promise(() => {})
    );
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('form').trigger('submit.prevent');
    await wrapper.find('form').trigger('submit.prevent');

    expect(KanbanBoardsAPI.createConversationCard).toHaveBeenCalledTimes(1);
  });

  it('closes the form and reloads cards after success', async () => {
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('form').trigger('submit.prevent');
    await flushPromises();

    expect(wrapper.text()).not.toContain('Create opportunity');
    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith('Opportunity created');
  });

  it('preserves filled values when the backend returns an error', async () => {
    KanbanBoardsAPI.createConversationCard.mockRejectedValue({
      response: { data: { message: 'Duplicate opportunity' } },
    });
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.find('input[type="text"]').setValue('Custom subject');
    await wrapper.find('form').trigger('submit.prevent');
    await flushPromises();

    expect(wrapper.text()).toContain('Duplicate opportunity');
    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Custom subject'
    );
  });

  it('resets the form and aborts pending requests when conversation changes', async () => {
    const boardSignals = [];
    KanbanBoardsAPI.getBoards.mockImplementation(config => {
      boardSignals.push(config.signal);
      return new Promise(() => {});
    });
    const wrapper = mountComponent();
    await flushPromises();
    await openForm(wrapper);

    await wrapper.setProps({ conversationId: 789 });

    expect(boardSignals[0].aborted).toBe(true);
    expect(wrapper.text()).not.toContain('Create opportunity');
  });

  it('opens an inline edit form automatically for an existing card', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    const wrapper = mountComponent();
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('labels/get');
    expect(KanbanBoardsAPI.showBoard).toHaveBeenCalledWith(10, {
      signal: expect.any(AbortSignal),
    });
    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Maria Silva - Sales Inbox'
    );
    expect(wrapper.find('select').element.value).toBe('20');
    expect(wrapper.findComponent({ name: 'LabelDropdown' }).exists()).toBe(
      true
    );
  });

  it('does not render an explicit edit button or pencil icon', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.find('button[aria-label="Edit opportunity"]').exists()).toBe(
      false
    );
    expect(wrapper.find('.i-lucide-pencil').exists()).toBe(false);
  });

  it('automatically saves inline card details and labels with PATCH requests', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await openEditForm(wrapper);
    KanbanBoardsAPI.updateCardDetailsById.mockClear();
    await wrapper.find('input[type="text"]').setValue('  Updated renewal  ');
    await flushPromises();
    await wrapper.find('select').setValue('20');
    await flushPromises();
    await wrapper
      .find('input[type="datetime-local"]')
      .setValue('2026-06-08T10:30');
    await flushPromises();
    await wrapper
      .findComponent({ name: 'LabelDropdown' })
      .vm.$emit('remove', 'urgente');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      123,
      {
        kanban_stage_id: 20,
        subject: 'Updated renewal',
        due_at: new Date('2026-06-08T10:30').toISOString(),
        labels: ['vendas'],
      }
    );
    expect(KanbanBoardsAPI.updateCardLabels).not.toHaveBeenCalled();
  });

  it('keeps inline edit values when saving fails', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    KanbanBoardsAPI.updateCardDetailsById.mockRejectedValue({
      response: { data: { message: 'Invalid stage' } },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await openEditForm(wrapper);
    await wrapper.find('input[type="text"]').setValue('Custom edit');
    await flushPromises();

    expect(wrapper.text()).toContain('Invalid stage');
    expect(wrapper.find('input[type="text"]').element.value).toBe(
      'Custom edit'
    );
  });

  it('preserves the edit form during realtime refresh', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    const wrapper = mountComponent();
    await flushPromises();
    await openEditForm(wrapper);
    await wrapper.find('input[type="text"]').setValue('Draft edit');

    emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { card_id: 123, conversation_id: 456 },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.getConversationCards).toHaveBeenCalledTimes(1);
    expect(wrapper.find('input[type="text"]').element.value).toBe('Draft edit');
  });

  it('does not save just by opening the inline edit form', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });
    const wrapper = mountComponent();
    await flushPromises();

    await openEditForm(wrapper);

    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="text"]').exists()).toBe(true);
  });
});
