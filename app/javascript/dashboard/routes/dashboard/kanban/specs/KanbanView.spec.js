import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import KanbanView from '../KanbanView.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

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
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    deleteStage: vi.fn(),
    createCard: vi.fn(),
    deleteCard: vi.fn(),
  },
}));

const buildBoardResponse = (stageBCards = []) => ({
  id: 10,
  name: 'Sales Board',
  description: '',
  stages: [
    {
      id: 100,
      name: 'Stage A',
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
      position: 2,
      cards: stageBCards,
    },
  ],
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
        WootDeleteModal: true,
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

describe('KanbanView drag and drop', () => {
  beforeEach(() => {
    vi.clearAllMocks();
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
    expect(panels[0].text()).toContain('KANBAN.ADD_ITEM.PLACEHOLDER');

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
