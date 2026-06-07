import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import KanbanConversationCards from '../KanbanConversationCards.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => {
      const translations = {
        'CONVERSATION_SIDEBAR.KANBAN.LOADING': 'Loading opportunities',
        'CONVERSATION_SIDEBAR.KANBAN.EMPTY':
          'No opportunities linked to this conversation',
        'CONVERSATION_SIDEBAR.KANBAN.ERROR': 'Failed to load opportunities',
      };

      return translations[key] || key;
    },
  }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    getConversationCards: vi.fn(),
  },
}));

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
  conversation_id: 456,
  ...overrides,
});

const mountComponent = (props = { conversationId: 456 }) =>
  mount(KanbanConversationCards, {
    props,
  });

describe('KanbanConversationCards', () => {
  beforeEach(() => {
    vi.resetAllMocks();
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
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [] },
    });
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

    expect(wrapper.text()).toContain('Fresh card');
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
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [] },
    });

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

  it('renders linked card row with subject, board, and stage', async () => {
    KanbanBoardsAPI.getConversationCards.mockResolvedValue({
      data: { payload: [buildCard()] },
    });

    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.text()).toContain('Maria Silva - Sales Inbox');
    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.text()).toContain('New');
    expect(wrapper.find('.bg-n-blue-9').exists()).toBe(true);
  });
});
