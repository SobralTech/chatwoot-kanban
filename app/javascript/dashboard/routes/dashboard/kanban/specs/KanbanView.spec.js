import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createStore } from 'vuex';
import KanbanView from '../KanbanView.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import kanbanBoardsModule from 'dashboard/store/modules/kanbanBoards';
import {
  KANBAN_STAGE_COLOR_OPTIONS,
  getKanbanStageColorClass,
} from 'dashboard/helper/kanbanStageColors';
import enKanbanMessages from 'dashboard/i18n/locale/en/kanban.json';
import ptBRKanbanMessages from 'dashboard/i18n/locale/pt_BR/kanban.json';

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
  frontendURL: path => path,
  conversationUrl: ({ accountId, id }) =>
    `/app/accounts/${accountId}/conversations/${id}`,
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
  agentRecords = buildAgents()
) =>
  createStore({
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
    },
  });

const buildPagination = (overrides = {}) => ({
  limit: 20,
  has_more: false,
  next_cursor: null,
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
      cards_count: 1,
      pagination: buildPagination(),
    },
    {
      id: 200,
      name: 'Stage B',
      active: true,
      position: 2,
      cards: stageBCards,
      cards_count: stageBCards.length,
      pagination: buildPagination(),
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
  KanbanBoardsAPI.reorderStage.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.reorderCardById.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.deleteCardById.mockResolvedValue({ data: {} });
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
        OnClickOutside: {
          template: '<div><slot /></div>',
        },
        Button: {
          name: 'Button',
          props: ['icon', 'label', 'color', 'size'],
          template:
            '<button v-bind="$attrs" class="btn-stub" @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
        TagMultiSelectComboBox: {
          name: 'TagMultiSelectComboBox',
          props: [
            'modelValue',
            'options',
            'disabled',
            'placeholder',
            'searchPlaceholder',
            'emptyState',
          ],
          template: '<div class="tag-multi-select-stub" />',
        },
        KanbanConversationCard: {
          name: 'KanbanConversationCard',
          props: {
            card: {
              type: Object,
              required: true,
            },
          },
          template: '<div class="kanban-card-stub" />',
        },
        KanbanOpportunityDetailsModal: {
          name: 'KanbanOpportunityDetailsModal',
          props: ['boardId', 'cardId'],
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
            '<div><slot /><slot name="item" v-for="(element, index) in draggableItems" :key="index" :element="element" :index="index" /></div>',
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

const findAddItemButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-add-item-button"]');

const findLoadMoreButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-load-more-cards"]');

const findAddItemPicker = wrapper =>
  wrapper.findComponent({ name: 'KanbanOpportunityPicker' });
const findInboxFilter = wrapper =>
  wrapper.findAllComponents({ name: 'TagMultiSelectComboBox' })[0];
const findAgentFilter = wrapper =>
  wrapper.findAllComponents({ name: 'TagMultiSelectComboBox' })[1];
const findInboxFilterWrapper = wrapper =>
  wrapper.find('[data-testid="kanban-inbox-filter"]');
const findAgentFilterWrapper = wrapper =>
  wrapper.find('[data-testid="kanban-agent-filter"]');

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
  await flushPromises();
  await nextTick();
};

describe('KanbanView realtime events', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
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
  });

  afterEach(() => {
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
    const targetStageCardDraggable = findCardDraggables(wrapper).find(
      draggable => draggable.props('list').length === 0
    );

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
    const emptyStageDraggable = findCardDraggables(wrapper).find(
      draggable => draggable.props('list').length === 0
    );

    expect(emptyStageDraggable.classes()).toContain('min-h-48');
    expect(emptyStageDraggable.text()).toContain('KANBAN.EMPTY_CARDS');
    expect(
      emptyStageDraggable.find('[data-testid="kanban-add-item-panel"]').exists()
    ).toBe(false);
    expect(emptyStageDraggable.props('emptyInsertThreshold')).toBe(80);
    expect(emptyStageDraggable.props('swapThreshold')).toBe(0.65);
    expect(emptyStageDraggable.props('fallbackOnBody')).toBe(true);
    expect(emptyStageDraggable.props('forceFallback')).toBe(true);
  });

  it('shows an add item action in each stage body', async () => {
    const wrapper = await mountView();
    const addItemButtons = findAddItemButtons(wrapper);

    expect(addItemButtons).toHaveLength(2);
    expect(addItemButtons[0].text()).toContain('KANBAN.ACTIONS.ADD_ITEM');
    expect(addItemButtons[1].text()).toContain('KANBAN.ACTIONS.ADD_ITEM');
  });

  it('opens and toggles the inline add item picker for the selected stage', async () => {
    const wrapper = await mountView();
    const addItemButtons = findAddItemButtons(wrapper);

    await addItemButtons[1].trigger('click');

    let picker = findAddItemPicker(wrapper);
    expect(picker.exists()).toBe(true);
    expect(picker.props('kanbanBoardId')).toBe(10);
    expect(picker.props('kanbanStageId')).toBe(200);

    await addItemButtons[1].trigger('click');

    picker = findAddItemPicker(wrapper);
    expect(picker.exists()).toBe(false);
  });

  it('closes the inline add item picker using the close action', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');
    expect(findAddItemPicker(wrapper).exists()).toBe(true);

    await findAddItemPicker(wrapper).vm.$emit('close');

    expect(findAddItemPicker(wrapper).exists()).toBe(false);
  });

  it('renders the add item picker outside card draggables', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');

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

    await findAddItemButtons(wrapper)[0].trigger('click');
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

    await findAddItemButtons(wrapper)[0].trigger('click');
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

    await findAddItemButtons(wrapper)[0].trigger('click');
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

    await findAddItemButtons(wrapper)[0].trigger('click');

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

  it('opens opportunity modal on card click', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityDetailsModal',
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
      path: '/app/accounts/1/conversations/123',
    });
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

  it('passes boardId and cardId to opportunity modal', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityDetailsModal',
    });
    expect(modal.props('boardId')).toBe(10);
    expect(modal.props('cardId')).toBe(501);
  });

  it('hides the outer opportunity modal close button', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({ name: 'WootModal' });
    expect(modal.props('showCloseButton')).toBe(false);
    expect(modal.props('size')).toBe('modal-big');
  });

  it('closes opportunity modal and clears selected card', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityDetailsModal',
    });
    modal.vm.$emit('close');
    await nextTick();

    expect(
      wrapper.findComponent({ name: 'KanbanOpportunityDetailsModal' }).exists()
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
      name: 'KanbanOpportunityDetailsModal',
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
      name: 'KanbanOpportunityDetailsModal',
    });
    KanbanBoardsAPI.show.mockClear();
    modal.vm.$emit('updated');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
    });
    expect(KanbanBoardsAPI.show).not.toHaveBeenCalled();
  });

  it('navigates to conversation on modal openConversation event', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityDetailsModal',
    });
    modal.vm.$emit('openConversation', { conversationId: 123 });
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/123',
    });
  });

  it('closes modal after navigating to conversation', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('openDetails', { id: 501, conversationId: 123 }, {});
    await nextTick();

    const modal = wrapper.findComponent({
      name: 'KanbanOpportunityDetailsModal',
    });
    modal.vm.$emit('openConversation', { conversationId: 123 });
    await flushPromises();

    expect(
      wrapper.findComponent({ name: 'KanbanOpportunityDetailsModal' }).exists()
    ).toBe(false);
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
    expect(dropdown.text()).not.toContain('KANBAN.OVERVIEW.CREATE_BOARD');
    expect(
      wrapper.find('[data-testid="kanban-board-dropdown-create"]').exists()
    ).toBe(false);
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
    expect(createStageButton.text()).toContain('KANBAN.ACTIONS.CREATE_STAGE');
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

  it('creates a stage with Nova etapa when that temporary name is available', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.NEW_STAGE_NAME': 'Nova etapa',
      };
      return translations[key] || key;
    });
    const wrapper = await mountView();
    const newStage = {
      id: 300,
      name: 'Nova etapa',
      active: true,
      position: 1,
      cards: [],
      cards_count: 0,
      pagination: buildPagination(),
    };
    KanbanBoardsAPI.createStage.mockResolvedValue({
      data: newStage,
    });
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], {
        stages: [newStage, ...buildBoardResponse().stages],
      }),
    });
    KanbanBoardsAPI.show.mockClear();

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await flushPromises();
    await nextTick();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Nova etapa',
        color: 'slate',
        position: 2,
      },
    });
    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
    const stageNameInput = wrapper
      .findAll('input')
      .find(
        input =>
          input.attributes('placeholder') ===
          'KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER'
      );
    expect(stageNameInput).toBeDefined();
    expect(stageNameInput.exists()).toBe(true);
    expect(stageNameInput.element.value).toBe('Nova etapa');
    expect(wrapper.text()).not.toContain('KANBAN.ACTIONS.CREATE_STAGE_CONFIRM');
  });

  it('creates a stage with Nova etapa (1) when Nova etapa already exists', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.NEW_STAGE_NAME': 'Nova etapa',
      };
      return translations[key] || key;
    });
    const existingStage = {
      ...buildBoardResponse().stages[0],
      id: 100,
      name: 'Nova etapa',
    };
    const newStage = {
      ...buildBoardResponse().stages[1],
      id: 300,
      name: 'Nova etapa (1)',
      cards: [],
      cards_count: 0,
    };
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: [existingStage, buildBoardResponse().stages[1]],
      })
    );
    KanbanBoardsAPI.createStage.mockResolvedValue({ data: newStage });
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], {
        stages: [newStage, existingStage, buildBoardResponse().stages[1]],
      }),
    });

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Nova etapa (1)',
        color: 'slate',
        position: 2,
      },
    });
  });

  it('creates a stage with Nova etapa (2) when previous temporary names exist', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.NEW_STAGE_NAME': 'Nova etapa',
      };
      return translations[key] || key;
    });
    const existingStages = [
      { ...buildBoardResponse().stages[0], id: 100, name: 'Nova etapa' },
      { ...buildBoardResponse().stages[1], id: 200, name: 'Nova etapa (1)' },
    ];
    const newStage = {
      ...buildBoardResponse().stages[1],
      id: 300,
      name: 'Nova etapa (2)',
      cards: [],
      cards_count: 0,
    };
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: existingStages,
      })
    );
    KanbanBoardsAPI.createStage.mockResolvedValue({ data: newStage });
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], {
        stages: [newStage, ...existingStages],
      }),
    });

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'Nova etapa (2)',
        color: 'slate',
        position: 2,
      },
    });
  });

  it('uses the translated English base for temporary stage names', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.NEW_STAGE_NAME': 'New stage',
      };
      return translations[key] || key;
    });
    const existingStage = {
      ...buildBoardResponse().stages[0],
      id: 100,
      name: 'New stage',
    };
    const newStage = {
      ...buildBoardResponse().stages[1],
      id: 300,
      name: 'New stage (1)',
      cards: [],
      cards_count: 0,
    };
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: [existingStage, buildBoardResponse().stages[1]],
      })
    );
    KanbanBoardsAPI.createStage.mockResolvedValue({ data: newStage });
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], {
        stages: [newStage, existingStage, buildBoardResponse().stages[1]],
      }),
    });

    await wrapper
      .find('[data-testid="kanban-create-stage-toggle"]')
      .trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.createStage).toHaveBeenCalledWith(10, {
      stage: {
        name: 'New stage (1)',
        color: 'slate',
        position: 2,
      },
    });
  });

  it('shows duplicate stage creation errors only as translated toast', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.ACTIONS.NEW_STAGE_NAME': 'Nova etapa',
        'KANBAN.ACTIONS.STAGE_NAME_TAKEN': 'Já existe uma etapa com esse nome.',
        'KANBAN.ACTIONS.CREATE_STAGE_ERROR':
          'Não foi possível criar a etapa do kanban.',
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
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Já existe uma etapa com esse nome.');
    expect(wrapper.text()).not.toContain('Name has already been taken');
    expect(wrapper.text()).not.toContain('Já existe uma etapa com esse nome.');
    expect(wrapper.find('.bg-n-ruby-2').exists()).toBe(false);
  });

  it('exposes the expanded stage color palette', () => {
    expect(KANBAN_STAGE_COLOR_OPTIONS.map(option => option.value)).toEqual([
      'slate',
      'blue',
      'teal',
      'green',
      'amber',
      'orange',
      'ruby',
      'rose',
      'violet',
      'iris',
    ]);
  });

  it('keeps rendering existing stage colors and falls back to slate', () => {
    expect(getKanbanStageColorClass('blue')).toBe('bg-n-blue-9');
    expect(getKanbanStageColorClass('unexpected')).toBe('bg-n-slate-9');
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

  it('renders board settings before the inbox filter', async () => {
    const wrapper = await mountView(buildBoardResponse(), 'administrator');
    const settingsButton = wrapper.find(
      '[data-testid="kanban-board-settings-button"]'
    );
    const inboxFilter = findInboxFilterWrapper(wrapper);

    expect(settingsButton.element.nextElementSibling).toBe(inboxFilter.element);
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
      name: 'kanban_board_settings',
      params: { accountId: '1', boardId: 10 },
    });
  });

  it('keeps board header filters compact', async () => {
    const wrapper = await mountView();
    const compactClasses = ['w-48', 'max-w-full', 'flex-none'];

    compactClasses.forEach(className => {
      expect(findInboxFilterWrapper(wrapper).classes()).toContain(className);
      expect(findAgentFilterWrapper(wrapper).classes()).toContain(className);
    });

    expect(findInboxFilterWrapper(wrapper).classes().join(' ')).not.toContain(
      'tag-multi-select-trigger'
    );
    expect(findAgentFilterWrapper(wrapper).classes().join(' ')).not.toContain(
      'tag-multi-select-trigger'
    );
  });

  it('does not open the board switcher when only one board is visible', async () => {
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
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-create-board-button"]').exists()
    ).toBe(false);
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
      '[data-testid="kanban-board-switcher-dropdown"] span'
    );
    expect(nameSpan.text()).toBe('Sales Board');
  });

  it('shows board name with title attribute for tooltip', async () => {
    const wrapper = await mountView();
    await wrapper
      .find('[data-testid="kanban-board-switcher"]')
      .trigger('click');
    const nameSpan = wrapper.find(
      '[data-testid="kanban-board-switcher-dropdown"] span'
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
      '[data-testid="kanban-board-switcher-dropdown"] span'
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

describe('KanbanView inbox filter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockT.mockImplementation(key => key);
    vi.useRealTimers();
    mockRoute.params.boardId = '10';
  });

  it('renders only allowed inbox options for selected_inboxes boards', async () => {
    const wrapper = await mountView({
      boardResponse: buildBoardResponse([], {
        inbox_scope_mode: 'selected_inboxes',
        allowed_inbox_ids: [2, 3],
      }),
    });

    expect(findInboxFilter(wrapper).props('options')).toEqual([
      { value: 2, label: 'Sales' },
      { value: 3, label: 'Onboarding' },
    ]);
  });

  it('refetches the board with inbox_ids when the filter changes', async () => {
    const wrapper = await mountView();

    KanbanBoardsAPI.show.mockClear();
    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2, 2]);
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: { inbox_ids: [2] },
    });
  });

  it('preserves inbox_ids on load more requests', async () => {
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

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2]);
    await flushPromises();
    KanbanBoardsAPI.getStageCards.mockClear();

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
      cursor: { after_id: 502 },
      inbox_ids: [2],
    });
  });

  it('preserves inbox_ids on realtime refreshes', async () => {
    const wrapper = await mountView();

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2]);
    await flushPromises();
    KanbanBoardsAPI.getStageCards.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 10, stage_id: 100, card_id: 700 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
      inbox_ids: [2],
    });
  });

  it('clears the inbox filter when switching boards', async () => {
    const wrapper = await mountView();

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2]);
    await flushPromises();
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], { id: 11, name: 'Renewals Board' }),
    });
    KanbanBoardsAPI.show.mockClear();
    mockRoute.params.boardId = '11';
    await flushPromises();

    expect(findInboxFilter(wrapper).props('modelValue')).toEqual([]);
    expect(KanbanBoardsAPI.show).toHaveBeenLastCalledWith(11, undefined);
  });

  it('removes inbox_ids when the filter is cleared', async () => {
    const wrapper = await mountView();

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2]);
    await flushPromises();
    KanbanBoardsAPI.show.mockClear();

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', []);
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, undefined);
  });
});

describe('KanbanView assignee filter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockT.mockImplementation(key => key);
    vi.useRealTimers();
    mockRoute.params.boardId = '10';
  });

  it('renders account agents as filter options', async () => {
    const wrapper = await mountView();

    expect(findAgentFilter(wrapper).props('options')).toEqual([
      { value: 7, label: 'Ada Lovelace' },
      { value: 8, label: 'Grace Hopper' },
    ]);
  });

  it('uses the translated agents filter placeholder', async () => {
    mockT.mockImplementation(key => {
      const translations = {
        'KANBAN.FILTERS.AGENTS': 'Agentes',
      };
      return translations[key] || key;
    });
    const wrapper = await mountView();

    expect(findAgentFilter(wrapper).props('placeholder')).toBe('Agentes');
    expect(mockT).toHaveBeenCalledWith('KANBAN.FILTERS.AGENTS');
  });

  it('defines agents filter labels for supported locales', () => {
    expect(enKanbanMessages.KANBAN.FILTERS.AGENTS).toBe('Agents');
    expect(ptBRKanbanMessages.KANBAN.FILTERS.AGENTS).toBe('Agentes');
  });

  it('refetches the board with assignee_ids when the filter changes', async () => {
    const wrapper = await mountView();

    KanbanBoardsAPI.show.mockClear();
    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7, 7]);
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: { assignee_ids: [7] },
    });
  });

  it('preserves assignee_ids on load more requests', async () => {
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

    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7]);
    await flushPromises();
    KanbanBoardsAPI.getStageCards.mockClear();

    await findLoadMoreButtonByStageId(wrapper, 200).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 200, {
      limit: 20,
      cursor: { after_id: 502 },
      assignee_ids: [7],
    });
  });

  it('preserves assignee_ids on realtime refreshes', async () => {
    const wrapper = await mountView();

    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7]);
    await flushPromises();
    KanbanBoardsAPI.getStageCards.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.created',
      data: { board_id: 10, stage_id: 100, card_id: 700 },
    });

    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
      assignee_ids: [7],
    });
  });

  it('uses a filtered server refresh for realtime card updates', async () => {
    const wrapper = await mountView();

    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7]);
    await flushPromises();
    KanbanBoardsAPI.showCardById.mockClear();
    KanbanBoardsAPI.getStageCards.mockClear();

    await emitKanbanRealtimeEvent({
      event: 'kanban.card.updated',
      data: { board_id: 10, stage_id: 100, card_id: 501 },
    });

    expect(KanbanBoardsAPI.showCardById).not.toHaveBeenCalled();
    expect(KanbanBoardsAPI.getStageCards).toHaveBeenCalledWith(10, 100, {
      limit: 20,
      assignee_ids: [7],
    });
  });

  it('clears the assignee filter when switching boards', async () => {
    const wrapper = await mountView();

    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7]);
    await flushPromises();
    KanbanBoardsAPI.show.mockResolvedValueOnce({
      data: buildBoardResponse([], { id: 11, name: 'Renewals Board' }),
    });
    KanbanBoardsAPI.show.mockClear();
    mockRoute.params.boardId = '11';
    await flushPromises();

    expect(findAgentFilter(wrapper).props('modelValue')).toEqual([]);
    expect(KanbanBoardsAPI.show).toHaveBeenLastCalledWith(11, undefined);
  });

  it('preserves inbox and assignee filters together', async () => {
    const wrapper = await mountView();

    await findInboxFilter(wrapper).vm.$emit('update:modelValue', [2]);
    await flushPromises();
    KanbanBoardsAPI.show.mockClear();

    await findAgentFilter(wrapper).vm.$emit('update:modelValue', [7]);
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10, {
      params: { inbox_ids: [2], assignee_ids: [7] },
    });
  });
});
