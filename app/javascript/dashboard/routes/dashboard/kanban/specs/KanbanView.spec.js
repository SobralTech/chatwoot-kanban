import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import KanbanView from '../KanbanView.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import ContactAPI from 'dashboard/api/contacts';

const mockPush = vi.fn();
const mockReplace = vi.fn();

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

vi.mock('dashboard/helper/URLHelper', () => ({
  frontendURL: path => path,
  conversationUrl: ({ accountId, id }) =>
    `/app/accounts/${accountId}/conversations/${id}`,
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    reorderStage: vi.fn(),
    reorderCard: vi.fn(),
    reorderCardById: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    deleteStage: vi.fn(),
    createCard: vi.fn(),
    deleteCard: vi.fn(),
    deleteCardById: vi.fn(),
  },
}));

vi.mock('dashboard/api/contacts', () => ({
  default: {
    search: vi.fn(),
  },
}));

const buildBoardResponse = (stageBCards = [], overrides = {}) => ({
  id: 10,
  name: 'Sales Board',
  description: '',
  default_stage_id: 200,
  auto_create_cards_from_conversations: true,
  use_opportunity_card_reads: false,
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
    },
    {
      id: 200,
      name: 'Stage B',
      active: true,
      position: 2,
      cards: stageBCards,
    },
  ],
  ...overrides,
});

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

const mountView = async (boardResponse = buildBoardResponse()) => {
  KanbanBoardsAPI.get.mockResolvedValue({
    data: [{ id: 10, name: 'Sales Board' }],
  });
  KanbanBoardsAPI.show.mockResolvedValue({
    data: boardResponse,
  });
  KanbanBoardsAPI.reorderStage.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.reorderCard.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.reorderCardById.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.deleteCard.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.deleteCardById.mockResolvedValue({ data: {} });

  const wrapper = shallowMount(KanbanView, {
    global: {
      stubs: {
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
  return wrapper;
};

const findCardDraggables = wrapper =>
  wrapper
    .findAllComponents({ name: 'Draggable' })
    .filter(draggable => draggable.props('handle') === '.card-drag-handle');

const findAddItemButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-add-item-button"]');

const findAddItemPanels = wrapper =>
  wrapper.findAll('[data-testid="kanban-add-item-panel"]');

const openAddItemPicker = async (wrapper, index = 0) => {
  await findAddItemButtons(wrapper)[index].trigger('click');
  return findAddItemPanels(wrapper)[0];
};

const findContactSearchInput = wrapper =>
  wrapper.find('[data-testid="kanban-contact-search-input"]');

const startBoardEdit = async wrapper => {
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('KANBAN.ACTIONS.EDIT_BOARD'))
    .trigger('click');
  await nextTick();
};

const findBoardEditForm = wrapper =>
  wrapper.find('[data-testid="kanban-board-edit-form"]');

const findAutoCreateToggle = wrapper =>
  wrapper.find('[data-testid="kanban-auto-create-toggle"]');

const findDefaultStageSelect = wrapper =>
  wrapper.find('[data-testid="kanban-default-stage-select"]');

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

    await draggables[0].vm.$emit('end', {
      item: { dataset: { stageId: '200' } },
      oldIndex: 1,
      newIndex: 0,
    });
    await flushPromises();

    expect(KanbanBoardsAPI.reorderStage).toHaveBeenCalledWith(10, 200, {
      position: 1,
    });
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

    expect(KanbanBoardsAPI.reorderCard).toHaveBeenCalledWith(10, 123, {
      card: {
        kanban_stage_id: 200,
        position: 1,
      },
    });
  });

  it('persists flagged cross-stage card drag using stable card id', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], { use_opportunity_card_reads: true })
    );
    const targetStageCardDraggable = findCardDraggables(wrapper).find(
      draggable => draggable.props('list').length === 0
    );

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
    expect(KanbanBoardsAPI.reorderCard).not.toHaveBeenCalled();
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

    let panels = findAddItemPanels(wrapper);
    expect(panels).toHaveLength(1);
    expect(panels[0].attributes('data-stage-id')).toBe('200');
    expect(
      panels[0].find('[data-testid="kanban-contact-search-input"]').exists()
    ).toBe(true);

    await addItemButtons[1].trigger('click');

    panels = findAddItemPanels(wrapper);
    expect(panels).toHaveLength(0);
  });

  it('closes the inline add item picker using the close action', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');
    expect(findAddItemPanels(wrapper)).toHaveLength(1);

    await wrapper.find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]').trigger('click');

    expect(findAddItemPanels(wrapper)).toHaveLength(0);
  });

  it('renders the add item picker outside card draggables', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');

    const cardDraggables = findCardDraggables(wrapper);
    expect(findAddItemPanels(wrapper)).toHaveLength(1);
    expect(
      cardDraggables.some(draggable =>
        draggable.find('[data-testid="kanban-add-item-panel"]').exists()
      )
    ).toBe(false);
  });

  it('does not trigger card drag behavior from add item controls', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');
    await wrapper.find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]').trigger('click');

    expect(KanbanBoardsAPI.reorderCard).not.toHaveBeenCalled();
  });

  it('shows a contact search input in the add item picker', async () => {
    const wrapper = await mountView();

    await openAddItemPicker(wrapper);

    expect(findContactSearchInput(wrapper).exists()).toBe(true);
    expect(findContactSearchInput(wrapper).attributes('placeholder')).toBe(
      'KANBAN.ADD_ITEM.PLACEHOLDER'
    );
    expect(
      wrapper
        .find('[data-testid="kanban-add-item-panel"] .i-lucide-search')
        .exists()
    ).toBe(false);
  });

  it('does not search contacts for queries shorter than three characters', async () => {
    vi.useFakeTimers();
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);
    const input = findContactSearchInput(wrapper);

    await input.setValue('');
    await input.setValue('J');
    await input.setValue('Ja');
    await vi.advanceTimersByTimeAsync(350);

    expect(ContactAPI.search).not.toHaveBeenCalled();
  });

  it('triggers a debounced contact search for three-character queries', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    expect(ContactAPI.search).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(ContactAPI.search).toHaveBeenCalledWith('Jan', 1, 'name', '', {
      signal: expect.any(AbortSignal),
    });
  });

  it('aborts stale contact search requests when query changes', async () => {
    vi.useFakeTimers();
    const signals = [];
    ContactAPI.search.mockImplementation((...args) => {
      signals.push(args[4].signal);
      return new Promise(() => {});
    });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);
    const input = findContactSearchInput(wrapper);

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);

    expect(signals[0].aborted).toBe(false);

    await input.setValue('Jane');

    expect(signals[0].aborted).toBe(true);
  });

  it('shows the contact search loading state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockReturnValue(new Promise(() => {}));
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');

    expect(
      wrapper.find('[data-testid="kanban-contact-search-loading"]').exists()
    ).toBe(true);
  });

  it('shows the contact search empty state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-contact-search-empty"]').text()
    ).toContain('KANBAN.ADD_ITEM.NO_CONTACTS');
  });

  it('shows the contact search error state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockRejectedValue(new Error('Search failed'));
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-contact-search-error"]').text()
    ).toContain('KANBAN.ADD_ITEM.SEARCH_ERROR');
  });

  it('renders compact contact search results', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            name: 'Jane Cooper',
            email: 'jane@example.com',
            phone_number: '+155501',
            thumbnail: 'https://example.com/jane.png',
          },
          { id: 2, name: 'John Doe', email: '', phone_number: '+155502' },
        ],
      },
    });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    const results = wrapper.find(
      '[data-testid="kanban-contact-search-results"]'
    );
    expect(results.text()).toContain('Jane Cooper');
    expect(results.text()).toContain('jane@example.com');
    expect(results.text()).toContain('+155501');
    expect(results.text()).toContain('John Doe');
    expect(results.text()).toContain('+155502');
    expect(results.find('img').attributes('src')).toBe(
      'https://example.com/jane.png'
    );
  });

  it('stores selected contact locally and shows the next-step placeholder', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({
      data: {
        payload: [{ id: 1, name: 'Jane Cooper', email: 'jane@example.com' }],
      },
    });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();
    await wrapper
      .find('[data-testid="kanban-contact-search-results"] button')
      .trigger('click');

    const selectedContact = wrapper.find(
      '[data-testid="kanban-selected-contact"]'
    );
    expect(selectedContact.text()).toContain('Jane Cooper');
    expect(selectedContact.text()).toContain(
      'KANBAN.ADD_ITEM.CONVERSATIONS_NEXT_STEP'
    );
  });

  it('clears the selected contact', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'Jane Cooper' }] },
    });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();
    await wrapper
      .find('[data-testid="kanban-contact-search-results"] button')
      .trigger('click');
    await wrapper
      .find('[aria-label="KANBAN.ADD_ITEM.CLEAR_CONTACT"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="kanban-selected-contact"]').exists()
    ).toBe(false);
    expect(findContactSearchInput(wrapper).exists()).toBe(true);
  });

  it('resets contact search state and aborts pending requests when closing picker', async () => {
    vi.useFakeTimers();
    const signals = [];
    ContactAPI.search.mockImplementation((...args) => {
      signals.push(args[4].signal);
      return new Promise(() => {});
    });
    const wrapper = await mountView();
    await openAddItemPicker(wrapper);

    await findContactSearchInput(wrapper).setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    expect(signals[0].aborted).toBe(false);

    await wrapper.find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]').trigger('click');

    expect(signals[0].aborted).toBe(true);

    await openAddItemPicker(wrapper);

    expect(findContactSearchInput(wrapper).element.value).toBe('');
    expect(
      wrapper.find('[data-testid="kanban-selected-contact"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-contact-search-loading"]').exists()
    ).toBe(false);
  });

  it('persists same-stage card reorder using updated position', async () => {
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

    expect(KanbanBoardsAPI.reorderCard).toHaveBeenCalledWith(10, 123, {
      card: {
        kanban_stage_id: 100,
        position: 1,
      },
    });
  });

  it('persists flagged same-stage card reorder using stable card id', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], { use_opportunity_card_reads: true })
    );
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
    expect(KanbanBoardsAPI.reorderCard).not.toHaveBeenCalled();
  });

  it('persists populated-to-populated stage card move', async () => {
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

    expect(KanbanBoardsAPI.reorderCard).toHaveBeenCalledWith(10, 123, {
      card: {
        kanban_stage_id: 200,
        position: 2,
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

    expect(KanbanBoardsAPI.reorderCard).not.toHaveBeenCalled();
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
    cardComponent.vm.$emit('openConversation', { conversationId: 123 }, {});
    await flushPromises();

    expect(mockPush).not.toHaveBeenCalled();
  });

  it('prevents overlapping card drag persistence requests', async () => {
    let resolveReorder;
    KanbanBoardsAPI.reorderCard.mockReturnValueOnce(
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

    expect(KanbanBoardsAPI.reorderCard).toHaveBeenCalledTimes(1);

    resolveReorder({ data: {} });
    await flushPromises();
  });

  it('removes flagged cards using stable card id', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], { use_opportunity_card_reads: true })
    );
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('removeCard', {
      id: 501,
      conversationId: 123,
      conversation: { meta: { sender: { name: 'Jane' } } },
    });
    await nextTick();
    await wrapper.find('[data-testid="confirm-delete"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.deleteCardById).toHaveBeenCalledWith(10, 501);
    expect(KanbanBoardsAPI.deleteCard).not.toHaveBeenCalled();
  });

  it('removes legacy cards using conversation id', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit('removeCard', {
      id: 501,
      conversationId: 123,
      conversation: { meta: { sender: { name: 'Jane' } } },
    });
    await nextTick();
    await wrapper.find('[data-testid="confirm-delete"]').trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.deleteCard).toHaveBeenCalledWith(10, 123);
    expect(KanbanBoardsAPI.deleteCardById).not.toHaveBeenCalled();
  });

  it('keeps card click navigation working', async () => {
    const wrapper = await mountView();
    const cardComponent = wrapper.findComponent({
      name: 'KanbanConversationCard',
    });

    cardComponent.vm.$emit(
      'openConversation',
      { conversationId: 123 },
      { metaKey: false, ctrlKey: false }
    );
    await flushPromises();

    expect(mockPush).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/123',
    });
  });
});

describe('KanbanView board edit form', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('renders the automation toggle', async () => {
    const wrapper = await mountView();

    await startBoardEdit(wrapper);

    expect(findAutoCreateToggle(wrapper).exists()).toBe(true);
    expect(wrapper.text()).toContain('KANBAN.BOARD_FORM.AUTO_CREATE_CARDS');
  });

  it('renders active stage options', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], {
        stages: [
          { id: 100, name: 'Stage A', active: true, position: 1, cards: [] },
          { id: 200, name: 'Stage B', active: false, position: 2, cards: [] },
        ],
      })
    );

    await startBoardEdit(wrapper);

    const options = findDefaultStageSelect(wrapper).findAll('option');
    expect(options).toHaveLength(1);
    expect(options[0].text()).toBe('Stage A');
  });

  it('selects the existing default stage', async () => {
    const wrapper = await mountView();

    await startBoardEdit(wrapper);

    expect(findDefaultStageSelect(wrapper).element.value).toBe('200');
  });

  it('sends automation configuration when saving', async () => {
    KanbanBoardsAPI.update.mockResolvedValue({
      data: {
        id: 10,
        name: 'Sales Board',
        description: '',
        auto_create_cards_from_conversations: false,
        default_stage_id: 100,
      },
    });
    const wrapper = await mountView();

    await startBoardEdit(wrapper);
    await findAutoCreateToggle(wrapper).setValue(false);
    await findDefaultStageSelect(wrapper).setValue('100');
    await findBoardEditForm(wrapper).trigger('submit.prevent');
    await flushPromises();

    expect(KanbanBoardsAPI.update).toHaveBeenCalledWith(10, {
      kanban_board: {
        name: 'Sales Board',
        description: '',
        auto_create_cards_from_conversations: false,
        default_stage_id: 100,
      },
    });
  });

  it('does not allow boards without stages to enable automation', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], {
        default_stage_id: null,
        auto_create_cards_from_conversations: false,
        stages: [],
      })
    );

    await startBoardEdit(wrapper);

    expect(findAutoCreateToggle(wrapper).attributes('disabled')).toBeDefined();
    expect(
      findDefaultStageSelect(wrapper).attributes('disabled')
    ).toBeDefined();
    expect(wrapper.text()).toContain('KANBAN.BOARD_FORM.NO_STAGES_HELP');
  });

  it('keeps the selected default stage when stages are reordered', async () => {
    const wrapper = await mountView();

    await startBoardEdit(wrapper);
    await findDefaultStageSelect(wrapper).setValue('200');

    const draggables = wrapper.findAllComponents({ name: 'Draggable' });
    await draggables[0].vm.$emit('end', {
      item: { dataset: { stageId: '200' } },
      oldIndex: 1,
      newIndex: 0,
    });
    await flushPromises();

    expect(findDefaultStageSelect(wrapper).element.value).toBe('200');
  });

  it('keeps existing board edit behavior working', async () => {
    KanbanBoardsAPI.update.mockResolvedValue({
      data: {
        id: 10,
        name: 'Updated Sales Board',
        description: 'Updated description',
        auto_create_cards_from_conversations: true,
        default_stage_id: 200,
      },
    });
    const wrapper = await mountView();

    await startBoardEdit(wrapper);
    const inputs = findBoardEditForm(wrapper).findAll('input');
    await inputs[0].setValue('Updated Sales Board');
    await inputs[1].setValue('Updated description');
    await findBoardEditForm(wrapper).trigger('submit.prevent');
    await flushPromises();

    expect(KanbanBoardsAPI.update).toHaveBeenCalledWith(10, {
      kanban_board: {
        name: 'Updated Sales Board',
        description: 'Updated description',
        auto_create_cards_from_conversations: true,
        default_stage_id: 200,
      },
    });
  });
});
