import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createStore } from 'vuex';
import KanbanView from '../KanbanView.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import kanbanBoardsModule from 'dashboard/store/modules/kanbanBoards';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import { FLUSH_DELAY } from 'dashboard/composables/useKanbanRealtimeBuffer';

const mockPush = vi.fn();
const mockReplace = vi.fn();
const mockT = vi.hoisted(() => vi.fn(key => key));
const mockRoute = reactive({
  params: {
    accountId: '1',
    boardId: '10',
  },
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: mockT,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({
    push: mockPush,
    replace: mockReplace,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => `/app/${path}`,
  conversationUrl: ({ accountId, id }) =>
    `accounts/${accountId}/conversations/${id}`,
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn(),
    off: vi.fn(),
  },
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    showBoard: vi.fn(),
    getSummary: vi.fn(),
    reorderStage: vi.fn(),
    reorderCardById: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    deleteStage: vi.fn(),
    getStageCards: vi.fn(),
    deleteCardById: vi.fn(),
    updateCardAssignees: vi.fn(),
    showCardById: vi.fn(),
  },
}));

KanbanBoardsAPI.showBoard = KanbanBoardsAPI.show;

const buildInboxes = () => [
  { id: 1, name: 'Support' },
  { id: 2, name: 'Sales' },
  { id: 3, name: 'Onboarding' },
];

const buildAgents = () => [
  { id: 7, name: 'Ada Lovelace', email: 'ada@example.com' },
  { id: 8, name: 'Grace Hopper', email: 'grace@example.com' },
];

const createTestStore = (
  role = 'agent',
  inboxRecords = buildInboxes(),
  agentRecords = buildAgents(),
  currentUserId = 7
) =>
  createStore({
    getters: {
      getCurrentRole: () => role,
      getCurrentUserID: () => currentUserId,
      getCurrentUser: () => ({ id: currentUserId, role }),
    },
    modules: {
      auth: {
        namespaced: true,
        getters: {
          getCurrentRole: () => role,
          getCurrentUserID: () => currentUserId,
          getCurrentUser: () => ({ id: currentUserId, role }),
        },
      },
      kanbanBoards: { namespaced: true, ...kanbanBoardsModule },
      inboxes: {
        namespaced: true,
        state: {
          records: inboxRecords,
        },
        getters: {
          getAllInboxes: state => state.records,
        },
        actions: {
          get: vi.fn(),
        },
      },
      agents: {
        namespaced: true,
        state: {
          records: agentRecords,
        },
        getters: {
          getAgents: state => state.records,
        },
        actions: {
          get: vi.fn(),
        },
      },
      labels: {
        namespaced: true,
        state: {
          records: [],
        },
        getters: {
          getLabels: state => state.records,
        },
        actions: {
          get: vi.fn(),
        },
      },
    },
  });

const buildPagination = (overrides = {}) => ({
  limit: 20,
  has_more: false,
  next_cursor: null,
  total_count: 0,
  ...overrides,
});

const buildBoardResponse = (stageBCards = [], overrides = {}) => ({
  id: 10,
  name: 'Sales Board',
  description: '',
  auto_create_cards_from_conversations: true,
  inbox_scope_mode: 'all_inboxes',
  allowed_inbox_ids: [],
  stages: [
    {
      id: 100,
      name: 'Stage A',
      active: true,
      position: 1,
      cards: [
        {
          id: 501,
          conversation_id: 123,
          kanban_stage_id: 100,
          position: 2,
          conversation: {
            inbox_id: 1,
            status: 'open',
            meta: { sender: { id: 1, name: 'Jane' } },
            messages: [{ content: 'hello' }],
          },
        },
      ],
      pagination: buildPagination({ total_count: 1 }),
    },
    {
      id: 200,
      name: 'Stage B',
      active: true,
      position: 2,
      cards: stageBCards,
      pagination: buildPagination({ total_count: stageBCards.length }),
    },
  ],
  ...overrides,
});

const buildBoards = (overrides = []) => [
  { id: 10, name: 'Sales Board' },
  { id: 11, name: 'Renewals Board' },
  ...overrides,
];

const buildCard = overrides => ({
  id: 502,
  conversation_id: 456,
  kanban_stage_id: 200,
  position: 1,
  conversation: {
    inbox_id: 1,
    status: 'open',
    meta: { sender: { id: 2, name: 'John' } },
    messages: [{ content: 'hi' }],
  },
  ...overrides,
});

const mountView = async (
  input = buildBoardResponse(),
  legacyRole = 'agent'
) => {
  const options =
    input &&
    typeof input === 'object' &&
    ['boardResponse', 'role', 'boards'].some(key => key in input)
      ? input
      : { boardResponse: input, role: legacyRole };
  const {
    boardResponse = buildBoardResponse(),
    role = 'agent',
    boards = buildBoards(),
    inboxes = buildInboxes(),
    agents = buildAgents(),
  } = options;

  KanbanBoardsAPI.get.mockResolvedValue({
    data: boards,
  });
  KanbanBoardsAPI.show.mockResolvedValue({
    data: boardResponse,
  });
  KanbanBoardsAPI.getSummary.mockResolvedValue({
    data: {
      open: { count: 1, value: '10.0' },
      won_this_month: { count: 1, value: '10.0' },
      lost_this_month: { count: 1, value: '10.0' },
      average_ticket: '10.00',
      currency: 'BRL',
    },
  });
  KanbanBoardsAPI.reorderStage.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.reorderCardById.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.deleteCardById.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.updateCardAssignees.mockResolvedValue({
    data: { payload: [] },
  });
  KanbanBoardsAPI.getStageCards.mockResolvedValue({
    data: { cards: [], pagination: buildPagination() },
  });
  KanbanBoardsAPI.showCardById.mockResolvedValue({
    data: buildCard({ id: 501, kanban_stage_id: 100 }),
  });

  const store = createTestStore(role, inboxes, agents);
  const dispatchSpy = vi.spyOn(store, 'dispatch');
  const wrapper = shallowMount(KanbanView, {
    global: {
      plugins: [store],
      stubs: {
        KanbanStageColumn: false,
        KanbanStageHeader: false,
        KanbanBoardHeader: false,
        KanbanStageDraft: false,
        OnClickOutside: {
          template: '<div><slot /></div>',
        },
        Button: {
          name: 'Button',
          props: ['icon', 'label', 'color', 'size'],
          template:
            '<button v-bind="$attrs" class="btn-stub" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
        KanbanFilterMenu: {
          name: 'KanbanFilterMenu',
          props: ['modelValue', 'inboxOptions', 'agentOptions', 'activeCount'],
          template:
            '<div class="kanban-filter-menu-stub"><span v-if="activeCount" data-testid="kanban-filter-count">{{ activeCount }}</span></div>',
        },
        KanbanStageMenu: {
          name: 'KanbanStageMenu',
          props: ['stage'],
          template:
            '<button data-testid="kanban-stage-menu-add-card" @click="$emit(\'addCard\')" />',
        },
        KanbanConversationCard: {
          name: 'KanbanConversationCard',
          props: {
            card: {
              type: Object,
              required: true,
            },
            isBusy: {
              type: Boolean,
              default: false,
            },
            stages: {
              type: Array,
              default: () => [],
            },
            assignableUsers: {
              type: Array,
              default: () => [],
            },
          },
          template: '<div class="kanban-card-stub" />',
        },
        KanbanOpportunityPanel: {
          name: 'KanbanOpportunityPanel',
          props: [
            'boardId',
            'cardId',
            'stages',
            'moveToStage',
            'hasBlockingDialog',
          ],
          data: () => ({ unsavedChanges: false }),
          computed: {
            hasUnsavedChanges() {
              return this.unsavedChanges;
            },
            unsavedFields() {
              return ['description'];
            },
          },
          methods: {
            saveCard: () => Promise.resolve(true),
          },
          template:
            '<div class="kanban-opportunity-modal-stub" data-board-id="{{ boardId }}" data-card-id="{{ cardId }}" />',
        },
        WootModal: {
          name: 'WootModal',
          props: ['show', 'showCloseButton', 'size'],
          template: '<div v-if="show" class="woot-modal-stub"><slot /></div>',
        },
        Draggable: {
          name: 'Draggable',
          props: {
            modelValue: {
              type: Array,
              default: () => [],
            },
            list: {
              type: Array,
              default: () => [],
            },
            handle: {
              type: String,
              default: '',
            },
            filter: {
              type: String,
              default: '',
            },
            preventOnFilter: {
              type: Boolean,
              default: true,
            },
            emptyInsertThreshold: {
              type: Number,
              default: 0,
            },
            swapThreshold: {
              type: Number,
              default: 1,
            },
            invertedSwapThreshold: {
              type: Number,
              default: 1,
            },
            fallbackOnBody: {
              type: Boolean,
              default: false,
            },
            forceFallback: {
              type: Boolean,
              default: false,
            },
            disabled: {
              type: Boolean,
              default: false,
            },
          },
          computed: {
            draggableItems() {
              return this.modelValue.length ? this.modelValue : this.list;
            },
          },
          template:
            '<div><slot name="item" v-for="(element, index) in draggableItems" :key="index" :element="element" :index="index" /><slot name="footer" /></div>',
        },
        WootDeleteModal: {
          name: 'WootDeleteModal',
          props: {
            show: {
              type: Boolean,
              default: false,
            },
            onConfirm: {
              type: Function,
              default: () => {},
            },
          },
          template:
            '<button v-if="show" data-testid="confirm-delete" @click="onConfirm" />',
        },
      },
      mocks: {
        window: { chatwootConfig: { hostURL: 'http://localhost:3000' } },
      },
    },
  });

  await flushPromises();
  await nextTick();
  wrapper.dispatchSpy = dispatchSpy;
  return wrapper;
};

const findCardDraggables = wrapper =>
  wrapper
    .findAllComponents({ name: 'Draggable' })
    .filter(draggable => draggable.props('handle') === '.card-drag-handle');

const findEmptyStageDraggable = wrapper =>
  findCardDraggables(wrapper).find(
    draggable => draggable.props('list').length === 0
  );

const findEmptyStageAddCard = wrapper =>
  findEmptyStageDraggable(wrapper).find(
    '[data-testid="kanban-empty-stage-add-card"]'
  );

const expectEmptyStageState = (wrapper, { hasAddCard, label }) => {
  expect(findEmptyStageAddCard(wrapper).exists()).toBe(hasAddCard);
  expect(findEmptyStageDraggable(wrapper).text()).toContain(label);
};

const findStageMenus = wrapper =>
  wrapper.findAllComponents({ name: 'KanbanStageMenu' });
const addCardFromStageMenu = (wrapper, index) =>
  findStageMenus(wrapper)
    [index].find('[data-testid="kanban-stage-menu-add-card"]')
    .trigger('click');

const findLoadMoreButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-load-more-cards"]');

const findAddItemPicker = wrapper =>
  wrapper.findComponent({ name: 'KanbanOpportunityPicker' });
const findFilterMenu = wrapper =>
  wrapper.findComponent({ name: 'KanbanFilterMenu' });
const updateBoardFilters = (wrapper, filters) =>
  findFilterMenu(wrapper).vm.$emit('update:modelValue', {
    ...findFilterMenu(wrapper).props('modelValue'),
    ...filters,
  });

const getStageCardIds = wrapper =>
  findCardDraggables(wrapper).map(draggable =>
    draggable.props('list').map(card => card.id)
  );

const getKanbanRealtimeHandler = () =>
  emitter.on.mock.calls.find(
    ([eventName]) => eventName === BUS_EVENTS.KANBAN_REALTIME_EVENT
  )?.[1];

const emitKanbanRealtimeEvent = async payload => {
  getKanbanRealtimeHandler()(payload);
  await vi.advanceTimersByTimeAsync(FLUSH_DELAY);
  await flushPromises();
  await nextTick();
};

beforeEach(() => {
  sessionStorage.clear();
});

describe('KanbanView realtime events', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  it('registers the kanban realtime bus listener on mount', async () => {
    await mountView();

    expect(emitter.on).toHaveBeenCalledWith(
      BUS_EVENTS.KANBAN_REALTIME_EVENT,
      expect.any(Function)
    );
  });

  it('removes the kanban realtime bus listener on unmount', async () => {
    const wrapper = await mountView();
    const handler = getKanbanRealtimeHandler();

    wrapper.unmount();

    expect(emitter.off).toHaveBeenCalledWith(
      BUS_EVENTS.KANBAN_REALTIME_EVENT,
      handler
    );
  });

  it('ignores events for another board', async () => {
    await mountView();
    KanbanBoardsAPI.show.mockClear();
    KanbanBoardsAPI.getStageCards.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 99, stage_id: 100, card_id: 501 },
    });

    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });

  it('refreshes selected board for board updates', async () => {
    await mountView();
    KanbanBoardsAPI.show.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.board.updated',
      data: { board_id: 10 },
    });

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });

  it.each([
    'kanban.stage.created',
    'kanban.stage.updated',
    'kanban.stage.deleted',
    'kanban.stage.reordered',
  ])('refreshes selected board for %s', async event => {
    await mountView();
    KanbanBoardsAPI.show.mockClear();

    await emitKanbanRealtimeEvent({
      event,
      data: { board_id: 10, stage_id: 100 },
    });

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });

  it('refreshes one stage for card created events', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 700, kanban_stage_id: 100 })],
        pagination: buildPagination({ total_count: 1 }),
      },
    });
    const wrapper = await mountView();
    KanbanBoardsAPI.show.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 10, stage_id: 100, card_id: 700 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(getStageCardIds(wrapper)).toEqual([[700], []]);
  });

  it('refreshes one stage for card deleted events', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: { cards: [], pagination: buildPagination({ total_count: 0 }) },
    });
    const wrapper = await mountView();
    KanbanBoardsAPI.show.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.deleted',
      data: { board_id: 10, stage_id: 100, card_id: 501 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(getStageCardIds(wrapper)).toEqual([[], []]);
  });

  it('refreshes one stage for same-stage card reorder events', async () => {
    await mountView();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.reordered',
      data: {
        board_id: 10,
        card_id: 501,
        source_stage_id: 100,
        target_stage_id: 100,
      },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledTimes(1);
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
  });

  it('refreshes two stages for cross-stage card reorder events', async () => {
    await mountView();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.reordered',
      data: {
        board_id: 10,
        card_id: 501,
        source_stage_id: 100,
        target_stage_id: 200,
      },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
    });
  });

  it('refreshes the funnel summary when a card moves between stages', async () => {
    await mountView();
    KanbanBoardsAPI.getSummary.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.reordered',
      data: {
        board_id: 10,
        card_id: 501,
        source_stage_id: 100,
        target_stage_id: 200,
      },
    });

    // Two stages refreshed, but the summary they share is only fetched once.
    expect(KanbanBoardsAPI.getSummary).toHaveBeenCalledTimes(1);
  });

  it('fetches card detail and patches visible cards for card updated events', async () => {
    KanbanBoardsAPI.showCardById.mockResolvedValueOnce({
      data: {
        id: 501,
        kanban_stage_id: 100,
        subject: 'Realtime subject',
        active: true,
      },
    });
    const wrapper = await mountView();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { board_id: 10, stage_id: 100, card_id: 501 },
    });

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
    expect(findCardDraggables(wrapper)[0].props('list')[0].subject).toBe(
      'Realtime subject'
    );
  });

  it('refreshes the stage when card updated detail fetch fails', async () => {
    KanbanBoardsAPI.showCardById.mockRejectedValueOnce(new Error('Not found'));
    await mountView();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { board_id: 10, stage_id: 100, card_id: 501 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
  });

  it('preserves other stages when a realtime stage refresh replaces page one', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 700, kanban_stage_id: 200 })],
        pagination: buildPagination({ has_more: true, total_count: 3 }),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          {
            ...buildBoardResponse().stages[0],
            cards: [buildCard({ id: 501, kanban_stage_id: 100 })],
            pagination: buildPagination({ has_more: true }),
          },
          {
            ...buildBoardResponse().stages[1],
            cards: [buildCard({ id: 502, kanban_stage_id: 200 })],
            cards_count: 2,
            pagination: buildPagination({ next_cursor: { after_id: 502 } }),
          },
        ],
      })
    );
    const firstStageCards = findCardDraggables(wrapper)[0].props('list');
    const firstStagePagination = wrapper.vm.$.setupState.stages[0].pagination;

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 10, stage_id: 200, card_id: 700 },
    });

    expect(findCardDraggables(wrapper)[0].props('list')).toEqual(
      firstStageCards
    );
    expect(wrapper.vm.$.setupState.stages[0].pagination).toEqual(
      firstStagePagination
    );
    expect(getStageCardIds(wrapper)[1]).toEqual([700]);
  });
});

const findLoadMoreButtonByStageId = (wrapper, stageId) =>
  findLoadMoreButtons(wrapper).find(
    button => Number(button.attributes('data-stage-id')) === stageId
  );

describe('KanbanView stage card pagination', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('renders the embedded first page without fetching stage cards', async () => {
    const wrapper = await mountView();

    const cards = wrapper.findAllComponents({ name: 'KanbanConversationCard' });

    expect(cards).toHaveLength(1);
    expect(cards[0].props('card').id).toBe(501);
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
  });

  it('shows load more only for stages with more cards', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: [
          {
            id: 100,
            name: 'Stage A',
            active: true,
            position: 1,
            cards: [buildCard({ id: 501, kanban_stage_id: 100 })],
            cards_count: 2,
            pagination: buildPagination({
              has_more: true,
              next_cursor: { after_id: 501 },
            }),
          },
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [],
            cards_count: 0,
            pagination: buildPagination(),
          },
        ],
      })
    );

    const loadMoreButtons = findLoadMoreButtons(wrapper);

    expect(loadMoreButtons).toHaveLength(1);
    expect(loadMoreButtons[0].attributes('data-stage-id')).toBe('100');
    expect(loadMoreButtons[0].text()).toContain(
      'KANBAN.ACTIONS.LOAD_MORE_CARDS'
    );
  });

  it('loads more cards with the stage cursor', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 503 })],
        pagination: buildPagination(),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({
              has_more: true,
              next_cursor: { after_id: 502 },
            }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
      cursor: { after_id: 502 },
    });
  });

  it('appends returned cards only to the target stage', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 503 })],
        pagination: buildPagination(),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    const cardLists = findCardDraggables(wrapper).map(draggable =>
      draggable.props('list').map(card => card.id)
    );
    expect(cardLists[0]).toEqual([501]);
    expect(cardLists[1]).toEqual([502, 503]);
  });

  it('does not append duplicate card ids twice', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard(), buildCard({ id: 503 })],
        pagination: buildPagination(),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(
      findCardDraggables(wrapper)[1]
        .props('list')
        .map(card => card.id)
    ).toEqual([502, 503]);
  });

  it('updates pagination metadata after loading more cards', async () => {
    KanbanBoardsAPI.getStageCards
      .mockResolvedValueOnce({
        data: {
          cards: [buildCard({ id: 503 })],
          pagination: buildPagination({
            has_more: true,
            next_cursor: { after_id: 503 },
          }),
        },
      })
      .mockResolvedValueOnce({
        data: {
          cards: [buildCard({ id: 504 })],
          pagination: buildPagination(),
        },
      });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 3,
            pagination: buildPagination({
              has_more: true,
              next_cursor: { after_id: 502 },
            }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();
    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenLastCalledWith(10, 200, {
      limit: 20,
      cursor: { after_id: 503 },
    });
    expect(findLoadMoreButtonByStageId(wrapper, 200)).toBeUndefined();
  });

  it('disables duplicate loads while a stage request is pending', async () => {
    let resolveLoadMore;
    KanbanBoardsAPI.getStageCards.mockReturnValueOnce(
      new Promise(resolve => {
        resolveLoadMore = resolve;
      })
    );
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledTimes(1);
    expect(
      findLoadMoreButtonByStageId(wrapper, 200).attributes('disabled')
    ).toBeDefined();

    resolveLoadMore({
      data: { cards: [buildCard({ id: 503 })], pagination: buildPagination() },
    });
    await flushPromises();
  });

  it('preserves loaded cards and shows an error on ordinary failure', async () => {
    KanbanBoardsAPI.getStageCards.mockRejectedValueOnce(new Error('Network'));
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(
      findCardDraggables(wrapper)[1]
        .props('list')
        .map(card => card.id)
    ).toEqual([502]);
    expect(wrapper.text()).toContain('KANBAN.ACTIONS.LOAD_CARDS_ERROR');
  });

  it('reloads the stage from page one on refresh_required conflicts', async () => {
    KanbanBoardsAPI.getStageCards
      .mockRejectedValueOnce({
        response: { status: 409, data: { error: 'refresh_required' } },
      })
      .mockResolvedValueOnce({
        data: {
          cards: [buildCard({ id: 600 })],
          pagination: buildPagination(),
        },
      });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({
              has_more: true,
              next_cursor: { after_id: 502 },
            }),
          },
        ],
      })
    );

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenNthCalledWith(1, 10, 200, {
      limit: 20,
      cursor: { after_id: 502 },
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenNthCalledWith(2, 10, 200, {
      limit: 20,
    });
    expect(
      findCardDraggables(wrapper)[1]
        .props('list')
        .map(card => card.id)
    ).toEqual([600]);
  });

  it('keeps other stages unchanged when a target stage reloads', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 503 })],
        pagination: buildPagination(),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    const firstStageBefore = findCardDraggables(wrapper)[0].props('list');

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(findCardDraggables(wrapper)[0].props('list')).toEqual(
      firstStageBefore
    );
  });

  it('updates cards count from returned total count on stage reload', async () => {
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({ has_more: true }),
          },
        ],
      })
    );

    KanbanBoardsAPI.getStageCards
      .mockRejectedValueOnce({
        response: { status: 409, data: { error: 'refresh_required' } },
      })
      .mockResolvedValueOnce({
        data: {
          cards: [buildCard({ id: 503 })],
          pagination: buildPagination({ total_count: 5 }),
        },
      });
    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(wrapper.vm.$.setupState.stages[1].cardsCount).toBe(5);
  });
});

describe('KanbanView drag and drop', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
    window.chatwootConfig = { hostURL: 'http://localhost:3000' };
    vi.spyOn(window, 'open').mockImplementation(() => null);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    delete window.chatwootConfig;
    vi.useRealTimers();
  });

  it('persists stage drag reorder using explicit position payload', async () => {
    const wrapper = await mountView();
    const draggables = wrapper.findAllComponents({ name: 'Draggable' });
    KanbanBoardsAPI.show.mockClear();

    await draggables[0].vm.$emit('end', {
      item: { dataset: { stageId: '200' } },
      oldIndex: 1,
      newIndex: 0,
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderStage).toHaveBeenCalledWith(10, 200, {
      position: 1,
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
  });

  it('persists cross-stage card drag using target stage and position payload', async () => {
    const wrapper = await mountView();
    const targetStageCardDraggable = findEmptyStageDraggable(wrapper);

    expect(targetStageCardDraggable).toBeDefined();

    targetStageCardDraggable.vm.$emit('change', {
      added: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 1,
        },
        newIndex: 0,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 200,
        position: 1,
      },
    });
  });

  it('makes the empty stage card list a configured drop zone', async () => {
    const wrapper = await mountView();
    const emptyStageDraggable = findEmptyStageDraggable(wrapper);

    // flex-1 makes the drop zone span the whole column instead of the former
    // min-h-48 island, so the dead space below the cards accepts drops too.
    expect(emptyStageDraggable.classes()).toContain('flex-1');
    expect(emptyStageDraggable.props('emptyInsertThreshold')).toBe(30);
    expect(emptyStageDraggable.props('swapThreshold')).toBe(0.65);
    expect(emptyStageDraggable.props('invertedSwapThreshold')).toBe(1);
    expect(emptyStageDraggable.props('fallbackOnBody')).toBe(true);
    expect(emptyStageDraggable.props('forceFallback')).toBe(true);
  });

  it('shows the add card action in an empty stage', async () => {
    const wrapper = await mountView();

    expect(findEmptyStageAddCard(wrapper).attributes('data-stage-id')).toBe(
      '200'
    );
  });

  it('opens the opportunity picker for an empty stage', async () => {
    const wrapper = await mountView();

    await findEmptyStageAddCard(wrapper).trigger('click');

    expect(findAddItemPicker(wrapper).props('kanbanStageId')).toBe(200);
  });

  it('shows a filtered empty state instead of the add card action', async () => {
    const wrapper = await mountView();

    await updateBoardFilters(wrapper, { inboxIds: [1] });
    await flushPromises();

    expectEmptyStageState(wrapper, {
      hasAddCard: false,
      label: 'KANBAN.EMPTY_CARDS_FILTERED',
    });
  });

  it('shows a filtered empty state while a search is active', async () => {
    const wrapper = await mountView();

    wrapper.vm.$.setupState.activeSearchTerm = 'sale';
    await nextTick();

    expectEmptyStageState(wrapper, {
      hasAddCard: false,
      label: 'KANBAN.EMPTY_CARDS_FILTERED',
    });
  });

  it('does not show the add card action for an empty terminal stage', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], { won_stage_id: 200 })
    );

    expectEmptyStageState(wrapper, {
      hasAddCard: false,
      label: 'KANBAN.EMPTY_CARDS',
    });
  });

  it('renders a list action menu in each stage header', async () => {
    const wrapper = await mountView();
    const stageMenus = findStageMenus(wrapper);

    expect(stageMenus).toHaveLength(2);
    expect(stageMenus[0].props('stage').id).toBe(100);
    expect(stageMenus[1].props('stage').id).toBe(200);
  });

  it('opens and toggles the manual picker from the selected list menu', async () => {
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 1);

    let picker = findAddItemPicker(wrapper);
    expect(picker.exists()).toBe(true);
    expect(picker.props('kanbanBoardId')).toBe(10);
    expect(picker.props('kanbanStageId')).toBe(200);

    await addCardFromStageMenu(wrapper, 1);

    picker = findAddItemPicker(wrapper);
    expect(picker.exists()).toBe(false);
  });

  it('closes the inline add item picker using the close action', async () => {
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 0);
    expect(findAddItemPicker(wrapper).exists()).toBe(true);

    await findAddItemPicker(wrapper).vm.$emit('close');

    expect(findAddItemPicker(wrapper).exists()).toBe(false);
  });

  it('renders the add item picker outside card draggables', async () => {
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 0);

    const cardDraggables = findCardDraggables(wrapper);
    expect(findAddItemPicker(wrapper).exists()).toBe(true);
    expect(
      cardDraggables.some(draggable =>
        draggable.findComponent({ name: 'KanbanOpportunityPicker' }).exists()
      )
    ).toBe(false);
  });

  it('does not trigger card drag behavior from add item controls', async () => {
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 0);
    await findAddItemPicker(wrapper).vm.$emit('close');

    expect(KanbanBoardsAPI.reorderCardById).not.toHaveBeenCalled();
  });

  it('refreshes only the target stage after a manual opportunity is created', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 700, kanban_stage_id: 100 })],
        pagination: buildPagination({ has_more: true, total_count: 2 }),
      },
    });
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 0);
    KanbanBoardsAPI.show.mockClear();

    await findAddItemPicker(wrapper).vm.$emit('created');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(getStageCardIds(wrapper)).toEqual([[700], []]);
  });

  it('replaces cards, pagination and extra pages after mutation refresh', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 700, kanban_stage_id: 100 })],
        pagination: buildPagination({
          has_more: true,
          next_cursor: { after_id: 700 },
          total_count: 3,
        }),
      },
    });
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: [
          {
            ...buildBoardResponse().stages[0],
            cards: [
              buildCard({ id: 501, kanban_stage_id: 100 }),
              buildCard({ id: 502, kanban_stage_id: 100 }),
            ],
            cards_count: 2,
            pagination: buildPagination(),
          },
          buildBoardResponse().stages[1],
        ],
      })
    );

    await addCardFromStageMenu(wrapper, 0);
    await findAddItemPicker(wrapper).vm.$emit('created');
    await flushPromises();

    expect(getStageCardIds(wrapper)[0]).toEqual([700]);
    expect(wrapper.vm.$.setupState.stages[0].pagination).toEqual({
      limit: 20,
      hasMore: true,
      nextCursor: { after_id: 700 },
      totalCount: 3,
    });
    expect(wrapper.vm.$.setupState.stages[0].cardsCount).toBe(3);
  });

  it('opens the manual picker for every board', async () => {
    const wrapper = await mountView();

    await addCardFromStageMenu(wrapper, 0);

    expect(findAddItemPicker(wrapper).exists()).toBe(true);
  });

  it('persists same-stage card reorder using updated position', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 501, kanban_stage_id: 100, position: 1 })],
        pagination: buildPagination({ total_count: 1 }),
      },
    });
    const wrapper = await mountView();
    const sourceStageCardDraggable = findCardDraggables(wrapper)[0];

    sourceStageCardDraggable.vm.$emit('change', {
      moved: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 2,
        },
        newIndex: 0,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 100,
        position: 1,
      },
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledTimes(1);
  });

  it('persists populated-to-populated stage card move', async () => {
    KanbanBoardsAPI.getStageCards.mockImplementation((boardId, stageId) => ({
      data: {
        cards: [buildCard({ id: stageId, kanban_stage_id: stageId })],
        pagination: buildPagination({ total_count: 1 }),
      },
    }));
    const wrapper = await mountView(buildBoardResponse([buildCard()]));
    const targetStageCardDraggable = findCardDraggables(wrapper)[1];

    targetStageCardDraggable.vm.$emit('change', {
      added: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 1,
        },
        newIndex: 1,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 200,
        position: 2,
      },
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledTimes(1);
  });
  it('persists filtered card drag using the card above the destination as anchor', async () => {
    const wrapper = await mountView(
      buildBoardResponse([
        buildCard({ id: 700, kanban_stage_id: 200, position: 4 }),
        buildCard({ id: 501, kanban_stage_id: 100, position: 1 }),
        buildCard({ id: 701, kanban_stage_id: 200, position: 9 }),
      ])
    );
    wrapper.vm.$.setupState.activeSearchTerm = 'sale';
    await nextTick();

    const targetStageCardDraggable = findCardDraggables(wrapper)[1];
    expect(targetStageCardDraggable.props('disabled')).toBe(false);

    targetStageCardDraggable.vm.$emit('change', {
      added: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 1,
        },
        newIndex: 1,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 200,
        after_card_id: 700,
      },
    });
  });

  it('persists filtered card drag to the top with a null anchor', async () => {
    const wrapper = await mountView(
      buildBoardResponse([buildCard({ id: 700, kanban_stage_id: 200 })])
    );
    wrapper.vm.$.setupState.activeSearchTerm = 'sale';
    await nextTick();

    const targetStageCardDraggable = findCardDraggables(wrapper)[1];
    targetStageCardDraggable.vm.$emit('change', {
      added: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 1,
        },
        newIndex: 0,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 200,
        after_card_id: null,
      },
    });
  });

  it('ignores source removed card drag events', async () => {
    const wrapper = await mountView();
    const sourceStageCardDraggable = findCardDraggables(wrapper)[0];

    sourceStageCardDraggable.vm.$emit('change', {
      removed: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 1,
        },
        oldIndex: 0,
      },
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).not.toHaveBeenCalled();
  });

  it('filters interactive controls from card drag start', async () => {
    const wrapper = await mountView();
    const cardDraggable = findCardDraggables(wrapper)[0];

    expect(cardDraggable.props('filter')).toBe(
      'button,a,input,textarea,select,[contenteditable="true"],.no-drag'
    );
    expect(cardDraggable.props('preventOnFilter')).toBe(false);
  });

  it('blocks click navigation immediately after card drag', async () => {
    const wrapper = await mountView();
    const cardDraggable = findCardDraggables(wrapper)[0];
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardDraggable.vm.$emit('start');
    cardDraggable.vm.$emit('end');
    cardComponent.vm.$emit('openDetails', { conversationId: 123 }, {});
    await flushPromises();

    expect(mockPush).not.toHaveBeenCalled();
  });

  it('prevents overlapping card drag persistence requests', async () => {
    let resolveReorder;
    KanbanBoardsAPI.reorderCardById.mockReturnValueOnce(
      new Promise(resolve => {
        resolveReorder = resolve;
      })
    );
    const wrapper = await mountView();
    const sourceStageCardDraggable = findCardDraggables(wrapper)[0];

    sourceStageCardDraggable.vm.$emit('change', {
      moved: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 2,
        },
        newIndex: 0,
      },
    });
    await nextTick();

    sourceStageCardDraggable.vm.$emit('change', {
      moved: {
        element: {
          id: 501,
          conversationId: 123,
          kanbanStageId: 100,
          position: 2,
        },
        newIndex: 0,
      },
    });

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledTimes(1);

    resolveReorder({ data: {} });
    await flushPromises();
  });

  it('removes cards using stable card id', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: { cards: [], pagination: buildPagination({ total_count: 0 }) },
    });
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('removeCard', {
      id: 501,
      kanbanStageId: 100,
      conversationId: 123,
      conversation: { meta: { sender: { name: 'Jane' } } },
    });
    await nextTick();
    await wrapper.find('[data-testid="confirm-delete"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.deleteCardById).toHaveBeenCalledWith(10, 501);
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledTimes(1);
  });
  it('moves a card to the top of another regular stage', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('moveToStage', { id: 501, kanbanStageId: 100 }, 200);
    await flushPromises();

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
      card: {
        kanban_stage_id: 200,
        after_card_id: null,
      },
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
    });
    expect(useAlert).toHaveBeenCalledWith('KANBAN.CARD.MOVE_SUCCESS');
  });

  it('updates visible assignees without reloading the board', async () => {
    KanbanBoardsAPI.updateCardAssignees.mockResolvedValueOnce({
      data: {
        payload: [{ id: 8, name: 'Grace Hopper', avatar_url: 'grace.png' }],
      },
    });
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });
    KanbanBoardsAPI.show.mockClear();

    cardComponent.vm.$emit(
      'assignAgent',
      { id: 501, kanbanStageId: 100, assignees: [] },
      8
    );
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardAssignees).toHaveBeenCalledWith(10, 501, [
      8,
    ]);
    expect(findCardDraggables(wrapper)[0].props('list')[0].assignees).toEqual([
      { id: 8, name: 'Grace Hopper', avatarUrl: 'grace.png' },
    ]);
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('KANBAN.CARD.ASSIGN_SUCCESS');
  });

  it('only marks the card with an active action as busy', async () => {
    let resolveAssignment;
    KanbanBoardsAPI.updateCardAssignees.mockReturnValueOnce(
      new Promise(resolve => {
        resolveAssignment = resolve;
      })
    );
    const wrapper = await mountView(
      buildBoardResponse([buildCard({ id: 502, kanban_stage_id: 200 })])
    );
    const cards = wrapper.findAllComponents({
      name: 'KanbanConversationCard',
    });

    cards[0].vm.$emit(
      'assignAgent',
      { id: 501, kanbanStageId: 100, assignees: [] },
      8
    );
    await nextTick();

    expect(cards[0].props('isBusy')).toBe(true);
    expect(cards[1].props('isBusy')).toBe(false);

    resolveAssignment({ data: { payload: [] } });
    await flushPromises();
  });

  it('opens opportunity modal on card click', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    expect(modal.exists()).toBe(true);
  });

  it('navigates to conversation on card openConversation event', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit(
      'openConversation',
      { id: 501, conversationId: 123 },
      {}
    );
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_conversation',
      params: {
        accountId: '1',
        boardId: 10,
        conversationId: 123,
      },
      state: { fromEmbedded: false },
    });
  });

  it('opens the standalone conversation URL in a new tab on ctrl-click', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit(
      'openConversation',
      { id: 501, conversationId: 123 },
      { ctrlKey: true }
    );
    await flushPromises();

    expect(window.open).toHaveBeenCalledWith(
      'http://localhost:3000/app/accounts/1/conversations/123',
      '_blank',
      'noopener,noreferrer'
    );
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('does not navigate from card openConversation event without conversationId', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openConversation', { id: 501 }, {});
    await flushPromises();

    expect(mockPush).not.toHaveBeenCalled();
  });

  it('passes boardId and cardId to opportunity panel', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    expect(modal.props('boardId')).toBe(10);
    expect(modal.props('cardId')).toBe(501);
  });

  it('mounts the opportunity panel without an outer modal', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    expect(
      wrapper.findComponent({ name: 'KanbanOpportunityPanel' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'WootModal' }).props('show')).toBe(
      false
    );
  });

  it('closes opportunity panel and clears selected card', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    modal.vm.$emit('close');
    await nextTick();

    expect(
      wrapper.findComponent({ name: 'KanbanOpportunityPanel' }).exists()
    ).toBe(false);
  });

  it('patches visible card locally on modal updated event', async () => {
    KanbanBoardsAPI.show.mockClear();
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    KanbanBoardsAPI.show.mockClear();
    modal.vm.$emit('updated', {
      id: 501,
      kanbanStageId: 100,
      subject: 'Updated subject',
    });
    await flushPromises();

    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getStageCards).not.toHaveBeenCalled();
    expect(findCardDraggables(wrapper)[0].props('list')[0].subject).toBe(
      'Updated subject'
    );
  });

  it('refreshes only the card stage when modal update cannot patch locally', async () => {
    KanbanBoardsAPI.getStageCards.mockResolvedValueOnce({
      data: {
        cards: [buildCard({ id: 501, kanban_stage_id: 100 })],
        pagination: buildPagination({ total_count: 1 }),
      },
    });
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    KanbanBoardsAPI.show.mockClear();
    modal.vm.$emit('updated');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
  });

  it('opens conversation in the same tab on modal openConversation event', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityPanel',
    });
    modal.vm.$emit('openConversation', { conversationId: 123 });
    await flushPromises();

    expect(window.open).not.toHaveBeenCalled();
    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_conversation',
      params: {
        accountId: '1',
        boardId: 10,
        conversationId: 123,
      },
      state: { fromEmbedded: false },
    });
  });

  it('guards modal conversation navigation when the opportunity has unsaved changes', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();
    const modal = wrapper.findComponent({ name: 'KanbanOpportunityPanel' });
    modal.vm.unsavedChanges = true;
    modal.vm.$emit('openConversation', { conversationId: 123 });
    await nextTick();

    expect(mockPush).not.toHaveBeenCalledWith(
      expect.objectContaining({ name: 'kanban_board_conversation' })
    );
    expect(wrapper.findComponent({ name: 'WootModal' }).props('show')).toBe(
      true
    );
  });

  it('opens a card deep link from the opportunity menu', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();
    const modal = wrapper.findComponent({ name: 'KanbanOpportunityPanel' });
    modal.vm.$emit('openFunnel', {
      id: 501,
      kanbanBoardId: 10,
    });
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: { accountId: '1', boardId: 10 },
      query: { card_id: 501 },
    });
  });
});

describe('KanbanView header navigation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockT.mockImplementation(key => key);
    vi.useRealTimers();
    mockRoute.params.boardId = '10';
  });

  it('shows the current board name', async () => {
    const wrapper = await mountView();

    expect(
      wrapper.find('[data-testid="kanban-board-switcher"]').text()
    ).toContain('Sales Board');
  });

  it('navigates to the funnels overview from the back button', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-back-to-overview"]')
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_boards',
      params: { accountId: '1' },
    });
  });

  it('lists visible boards in the dropdown', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');

    const dropdown = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"]'
    );
    expect(dropdown.exists()).toBe(true);
    expect(dropdown.text()).toContain('Sales Board');
    expect(dropdown.text()).toContain('Renewals Board');
    expect(dropdown.text()).toContain('KANBAN.OVERVIEW.CREATE_BOARD');
    expect(
      wrapper.find('[data-testid="kanban-board-switcher-create-new"]').exists()
    ).toBe(true);
  });

  it('navigates to the create board form from the dropdown', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-board-switcher-create-new"]')
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_create_form',
      params: { accountId: '1' },
    });
  });

  it('does not render a create board button in the board header', async () => {
    const wrapper = await mountView();

    expect(
      wrapper.find('[data-testid="kanban-create-board-button"]').exists()
    ).toBe(false);
  });

  it('does not mount the reusable create board dialog on the board page', async () => {
    const wrapper = await mountView();

    expect(
      wrapper.findComponent({ name: 'KanbanCreateBoardDialog' }).exists()
    ).toBe(false);
  });

  it('does not offer board creation from the empty board state', async () => {
    mockRoute.params.boardId = undefined;
    const wrapper = await mountView({ boardResponse: null, boards: [] });

    expect(
      wrapper.find('[data-testid="kanban-empty-create-board-button"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-create-board-button"]').exists()
    ).toBe(false);
    expect(
      wrapper.findComponent({ name: 'KanbanCreateBoardDialog' }).exists()
    ).toBe(false);
  });

  it('shows a dedicated create stage button in the header', async () => {
    const wrapper = await mountView();

    const createStageButton = wrapper.find(
      '[data-testid="kanban-create-stage-toggle"]'
    );

    expect(createStageButton.exists()).toBe(true);
    expect(createStageButton.attributes('aria-label')).toBe(
      'KANBAN.ACTIONS.CREATE_STAGE'
    );
  });

  it('does not render the old separate create stage form', async () => {
    const wrapper = await mountView();

    expect(wrapper.text()).not.toContain('KANBAN.ACTIONS.CREATE_STAGE_CONFIRM');
    expect(
      wrapper
        .findAll('input')
        .some(
          input =>
            input.attributes('placeholder') ===
            'KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER'
        )
    ).toBe(false);
  });

  it('navigates when switching boards from the dropdown', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-board-switcher-dropdown"]')
      .findAll('button')[1]
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_show',
      params: {
        accountId: '1',
        boardId: 11,
      },
    });
  });

  it('returns to the kanban overview when the board is inaccessible', async () => {
    const wrapper = await mountView();
    KanbanBoardsAPI.show.mockRejectedValueOnce({
      response: { status: 404 },
    });

    await wrapper.vm.$.setupState.showBoard(99);

    expect(mockReplace).toHaveBeenCalledWith({
      name: 'kanban_boards',
      params: { accountId: '1' },
    });
  });

  it('opens a blank stage draft without creating a stage', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await nextTick();

    expect(KanbanBoardsAPI.createStage).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-new-stage-name-input"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-new-stage-name-input"]').element.value
    ).toBe('');
    expect(
      wrapper.find('[data-testid="kanban-create-stage-confirm"]').exists()
    ).toBe(true);
  });

  it('creates a stage only after confirming its draft name', async () => {
    const newStage = {
      ...buildBoardResponse().stages[1],
      id: 300,
      name: 'Negotiation',
      cards: [],
      cards_count: 0,
    };
    const wrapper = await mountView();
    KanbanBoardsAPI.createStage.mockResolvedValue({ data: newStage });
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], {
        stages: [newStage, ...buildBoardResponse().stages],
      }),
    });
    KanbanBoardsAPI.show.mockClear();

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-new-stage-name-input"]')
      .setValue('Negotiation');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Negotiation',
        color: '#8B8D98',
        position: 2,
      },
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    expect(
      wrapper.find('[data-testid="kanban-new-stage-name-input"]').exists()
    ).toBe(false);
  });

  it('cancels a stage draft without creating a stage', async () => {
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-new-stage-name-input"]')
      .setValue('Negotiation');
    await wrapper
      .find('[data-testid="kanban-create-stage-cancel"]')
      .trigger('click');

    expect(KanbanBoardsAPI.createStage).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-new-stage-name-input"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-create-stage-draft"]').exists()
    ).toBe(true);
  });

  it('keeps a duplicate stage draft open with its name', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.STAGE_NAME_TAKEN':
          'A stage with this name already exists.',
        'KANBAN.ACTIONS.CREATE_STAGE_ERROR':
          'Could not create the kanban stage.',
      };
      return translations[key] || key;
    });
    KanbanBoardsAPI.createStage.mockRejectedValue({
      response: { data: { error: 'Name has already been taken' } },
    });
    const wrapper = await mountView();

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="kanban-new-stage-name-input"]')
      .setValue('Stage A');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'A stage with this name already exists.'
    );
    expect(
      wrapper.find('[data-testid="kanban-new-stage-name-input"]').element.value
    ).toBe('Stage A');
  });

  it('keeps stage editing open and warns when the name is empty', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.STAGE_NAME_REQUIRED': 'Enter a name for the stage.',
      };
      return translations[key] || key;
    });
    const wrapper = await mountView();
    const stage = buildBoardResponse().stages[0];

    wrapper.vm.$.setupState.startEditingStage(stage);
    await nextTick();
    wrapper.vm.$.setupState.stageNames[stage.id] = '';
    await wrapper.vm.$.setupState.updateStage(stage);

    expect(useAlert).toHaveBeenCalledWith('Enter a name for the stage.');
    expect(wrapper.vm.$.setupState.editingStageId).toBe(stage.id);
    expect(KanbanBoardsAPI.updateStage).not.toHaveBeenCalled();
  });

  it('clears the stage edit draft when editing is cancelled', async () => {
    const wrapper = await mountView();
    const stage = buildBoardResponse().stages[0];

    wrapper.vm.$.setupState.startEditingStage(stage);
    wrapper.vm.$.setupState.stageNames[stage.id] = 'Changed';
    wrapper.vm.$.setupState.cancelEditingStage();

    expect(wrapper.vm.$.setupState.editingStageId).toBe(null);
    expect(wrapper.vm.$.setupState.stageNames[stage.id]).toBeUndefined();
    expect(wrapper.vm.$.setupState.stageColors[stage.id]).toBeUndefined();
  });

  it('uses a hexadecimal default stage color', () => {
    expect(DEFAULT_KANBAN_STAGE_COLOR).toBe('#8B8D98');
  });

  it('shows board settings button for administrators', async () => {
    const wrapper = await mountView(buildBoardResponse(), 'administrator');
    const settingsButton = wrapper.find(
      '[data-testid="kanban-board-settings-button"]'
    );

    expect(settingsButton.exists()).toBe(true);
    expect(settingsButton.element.tagName).toBe('BUTTON');
    expect(settingsButton.classes()).toEqual(
      expect.arrayContaining([
        'size-10',
        'rounded-lg',
        'text-n-slate-11',
        'hover:bg-n-alpha-2',
      ])
    );
    expect(settingsButton.find('.i-lucide-settings').classes()).toContain(
      'size-4'
    );
  });

  it('renders board settings after the filter menu and before create stage', async () => {
    const wrapper = await mountView(buildBoardResponse(), 'administrator');
    const settingsButton = wrapper.find(
      '[data-testid="kanban-board-settings-button"]'
    );
    const filterMenu = wrapper.find(
      '[data-testid="kanban-filter-menu-container"]'
    );
    const createStageButton = wrapper.find(
      '[data-testid="kanban-create-stage-toggle"]'
    );

    expect(filterMenu.element.nextElementSibling).toBe(settingsButton.element);
    expect(settingsButton.element.nextElementSibling).toBe(
      createStageButton.element
    );
  });

  it('does not show board settings button for agents', async () => {
    const wrapper = await mountView(buildBoardResponse(), 'agent');

    expect(
      wrapper.find('[data-testid="kanban-board-settings-button"]').exists()
    ).toBe(false);
  });

  it('opens board settings route from the settings button', async () => {
    const wrapper = await mountView(buildBoardResponse(), 'administrator');

    await wrapper
      .find('[data-testid="kanban-board-settings-button"]')
      .trigger('click');

    expect(mockPush).toHaveBeenCalledWith({
      name: 'kanban_board_edit_form',
      params: { accountId: '1', boardId: 10 },
    });
  });

  it('renders the unified board filter menu', async () => {
    const wrapper = await mountView();

    expect(findFilterMenu(wrapper).exists()).toBe(true);
    expect(wrapper.find('[data-testid="kanban-inbox-filter"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="kanban-agent-filter"]').exists()).toBe(
      false
    );
  });

  it('still opens the board switcher to create a board when only one board is visible', async () => {
    const wrapper = await mountView({
      boards: [{ id: 10, name: 'Sales Board' }],
    });

    expect(
      wrapper.find('[data-testid="kanban-board-switcher"]').text()
    ).toContain('Sales Board');
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    expect(
      wrapper.find('[data-testid="kanban-board-switcher-dropdown"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-board-switcher-create-new"]').exists()
    ).toBe(true);
  });

  it('does not render an internal sidebar', async () => {
    const wrapper = await mountView();
    expect(wrapper.find('aside').exists()).toBe(false);
  });

  it('does not render board description below the name', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], { description: 'Pipeline description' })
    );
    expect(wrapper.text()).not.toContain('Pipeline description');
  });

  it('renders the dropdown with extra width', async () => {
    const wrapper = await mountView();
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    const dropdown = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"]'
    );
    expect(dropdown.classes()).toContain('w-96');
  });

  it('displays short board name without truncation in dropdown', async () => {
    const wrapper = await mountView();
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    const nameSpan = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"] button'
    );
    expect(nameSpan.text()).toBe('Sales Board');
  });

  it('shows board name with title attribute for tooltip', async () => {
    const wrapper = await mountView();
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    const nameSpan = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"] button'
    );
    expect(nameSpan.attributes('title')).toBe('Sales Board');
  });

  it('displays long board name with ellipsis classes and title', async () => {
    const wrapper = await mountView({
      boards: [
        { id: 10, name: 'Very Long Board Name That Exceeds Available Width' },
        { id: 11, name: 'Short' },
      ],
    });
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    const nameSpan = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"] button'
    );
    expect(nameSpan.text()).toBe(
      'Very Long Board Name That Exceeds Available Width'
    );
    expect(nameSpan.attributes('title')).toBe(
      'Very Long Board Name That Exceeds Available Width'
    );
    expect(nameSpan.classes()).toContain('overflow-hidden');
    expect(nameSpan.classes()).toContain('text-ellipsis');
    expect(nameSpan.classes()).toContain('whitespace-nowrap');
  });
});

describe('KanbanView filters', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockT.mockImplementation(key => key);
    vi.useFakeTimers();
    mockRoute.params.boardId = '10';
    window.localStorage.clear();
  });

  it('passes board-scoped inbox and agent options to the filter menu', async () => {
    const wrapper = await mountView({
      boardResponse: buildBoardResponse([], {
        inbox_scope_mode: 'selected_inboxes',
        allowed_inbox_ids: [2, 3],
      }),
    });

    expect(findFilterMenu(wrapper).props('inboxOptions')).toEqual([
      { value: 2, label: 'Sales' },
      { value: 3, label: 'Onboarding' },
    ]);
    expect(findFilterMenu(wrapper).props('agentOptions')).toEqual([
      { value: 7, label: 'Ada Lovelace' },
      { value: 8, label: 'Grace Hopper' },
    ]);
    expect(wrapper.dispatchSpy).toHaveBeenCalledWith('labels/get');

    expect(findFilterMenu(wrapper).props('modelValue')).toMatchObject({
      matchMode: 'any',
    });
  });

  it('refetches with all selected filter categories and match mode', async () => {
    const wrapper = await mountView();

    KanbanBoardsAPI.show.mockClear();
    await updateBoardFilters(wrapper, {
      inboxIds: [2],
      assigneeIds: [7],
      cardStatuses: ['open'],
      priorities: ['high'],
      dueDates: ['week'],
      labels: ['vip'],
      matchMode: 'any',
    });
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: {
        inbox_ids: [2],
        assignee_ids: [7],
        card_statuses: ['open'],
        priorities: ['high'],
        due_dates: ['week'],
        labels: ['vip'],
        match_mode: 'any',
      },
    });
    expect(wrapper.find('[data-testid="kanban-filter-count"]').text()).toBe(
      '6'
    );
  });

  it('preserves active filters on load more and realtime refreshes', async () => {
    const wrapper = await mountView(
      buildBoardResponse([buildCard()], {
        stages: [
          buildBoardResponse().stages[0],
          {
            id: 200,
            name: 'Stage B',
            active: true,
            position: 2,
            cards: [buildCard()],
            cards_count: 2,
            pagination: buildPagination({
              has_more: true,
              next_cursor: { after_id: 502 },
            }),
          },
        ],
      })
    );

    await updateBoardFilters(wrapper, {
      priorities: ['high'],
      matchMode: 'all',
    });
    await flushPromises();
    KanbanBoardsAPI.getStageCards.mockClear();

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
      cursor: { after_id: 502 },
      priorities: ['high'],
      match_mode: 'all',
    });

    KanbanBoardsAPI.getStageCards.mockClear();
    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 10, stage_id: 100, card_id: 700 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
      priorities: ['high'],
      match_mode: 'all',
    });
  });

  it('clears all board filters from the header action', async () => {
    const wrapper = await mountView();

    await updateBoardFilters(wrapper, { inboxIds: [2] });
    await flushPromises();
    KanbanBoardsAPI.show.mockClear();

    await wrapper.find('[data-testid="kanban-clear-filters"]').trigger('click');
    await flushPromises();

    expect(findFilterMenu(wrapper).props('modelValue')).toEqual({
      inboxIds: [],
      assigneeIds: [],
      cardStatuses: [],
      priorities: [],
      stageSla: [],
      dueDates: [],
      labels: [],
      matchMode: 'any',
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
  });

  it('resets filters when switching boards', async () => {
    const wrapper = await mountView();

    await updateBoardFilters(wrapper, { assigneeIds: [7] });
    await flushPromises();
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], { id: 11, name: 'Renewals Board' }),
    });
    KanbanBoardsAPI.show.mockClear();
    mockRoute.params.boardId = '11';
    await flushPromises();

    expect(findFilterMenu(wrapper).props('modelValue')).toEqual({
      inboxIds: [],
      assigneeIds: [],
      cardStatuses: [],
      priorities: [],
      stageSla: [],
      dueDates: [],
      labels: [],
      matchMode: 'any',
    });
    expect(KanbanBoardsAPI.show).toHaveBeenLastCalledWith(11, undefined);
  });

  it('toggles Mine quick filter on and off', async () => {
    const wrapper = await mountView();
    const mineButton = wrapper.find('[data-testid="kanban-filter-mine"]');

    KanbanBoardsAPI.show.mockClear();
    await mineButton.trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: {
        assignee_ids: [7],
        match_mode: 'all',
      },
    });
    expect(mineButton.classes()).toContain('text-n-brand');
    expect(findFilterMenu(wrapper).props('modelValue')).toMatchObject({
      assigneeIds: [7],
      matchMode: 'all',
    });

    KanbanBoardsAPI.show.mockClear();
    await mineButton.trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    expect(mineButton.classes()).not.toContain('text-n-brand');
    expect(findFilterMenu(wrapper).props('modelValue')).toMatchObject({
      assigneeIds: [],
    });
  });

  it('toggles Today quick filter on and off with card count badge', async () => {
    const wrapper = await mountView();
    const todayButton = wrapper.find('[data-testid="kanban-filter-today"]');

    expect(wrapper.find('[data-testid="kanban-today-count"]').exists()).toBe(
      false
    );

    KanbanBoardsAPI.show.mockClear();
    await todayButton.trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: {
        card_statuses: ['open'],
        due_dates: ['overdue', 'day'],
        match_mode: 'all',
      },
    });
    expect(todayButton.classes()).toContain('text-n-brand');
    expect(wrapper.find('[data-testid="kanban-today-count"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="kanban-today-count"]').text()).toBe('1');
    expect(findFilterMenu(wrapper).props('modelValue')).toMatchObject({
      dueDates: ['overdue', 'day'],
      cardStatuses: ['open'],
      matchMode: 'all',
    });

    KanbanBoardsAPI.show.mockClear();
    await todayButton.trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    expect(todayButton.classes()).not.toContain('text-n-brand');
    expect(wrapper.find('[data-testid="kanban-today-count"]').exists()).toBe(
      false
    );
  });

  it('applies Mine and Today together with match all', async () => {
    const wrapper = await mountView();
    const mineButton = wrapper.find('[data-testid="kanban-filter-mine"]');
    const todayButton = wrapper.find('[data-testid="kanban-filter-today"]');

    await mineButton.trigger('click');
    await flushPromises();

    KanbanBoardsAPI.show.mockClear();
    await todayButton.trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: {
        assignee_ids: [7],
        card_statuses: ['open'],
        due_dates: ['overdue', 'day'],
        match_mode: 'all',
      },
    });
    expect(mineButton.classes()).toContain('text-n-brand');
    expect(todayButton.classes()).toContain('text-n-brand');
  });

  it('clears Mine and Today when clear all is clicked', async () => {
    const wrapper = await mountView();
    const mineButton = wrapper.find('[data-testid="kanban-filter-mine"]');
    const todayButton = wrapper.find('[data-testid="kanban-filter-today"]');

    await mineButton.trigger('click');
    await todayButton.trigger('click');
    await flushPromises();

    expect(mineButton.classes()).toContain('text-n-brand');
    expect(todayButton.classes()).toContain('text-n-brand');

    KanbanBoardsAPI.show.mockClear();
    await wrapper.find('[data-testid="kanban-clear-filters"]').trigger('click');
    await flushPromises();

    expect(mineButton.classes()).not.toContain('text-n-brand');
    expect(todayButton.classes()).not.toContain('text-n-brand');
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
  });

  it('restores quick filter preferences from localStorage on mount', async () => {
    window.localStorage.setItem(
      'kanban_board_prefs_1_10_7',
      JSON.stringify({ mine: true, today: true })
    );

    KanbanBoardsAPI.show.mockClear();
    const wrapper = await mountView();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledTimes(1);
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: {
        assignee_ids: [7],
        card_statuses: ['open'],
        due_dates: ['overdue', 'day'],
        match_mode: 'all',
      },
    });

    const mineButton = wrapper.find('[data-testid="kanban-filter-mine"]');
    const todayButton = wrapper.find('[data-testid="kanban-filter-today"]');
    expect(mineButton.classes()).toContain('text-n-brand');
    expect(todayButton.classes()).toContain('text-n-brand');

    window.localStorage.removeItem('kanban_board_prefs_1_10_7');
  });
});
