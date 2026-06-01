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
    reorderCardById: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    createStage: vi.fn(),
    updateStage: vi.fn(),
    deleteStage: vi.fn(),
    deleteCardById: vi.fn(),
  },
}));

const buildBoardResponse = (stageBCards = [], overrides = {}) => ({
  id: 10,
  name: 'Sales Board',
  description: '',
  auto_create_cards_from_conversations: true,
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
  KanbanBoardsAPI.reorderCardById.mockResolvedValue({ data: {} });
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
        KanbanOpportunityDetailsModal: {
          name: 'KanbanOpportunityDetailsModal',
          props: ['boardId', 'cardId'],
          template:
            '<div class="kanban-opportunity-modal-stub" data-board-id="{{ boardId }}" data-card-id="{{ cardId }}" />',
        },
        WootModal: {
          name: 'WootModal',
          props: ['show'],
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
  return wrapper;
};

const findCardDraggables = wrapper =>
  wrapper
    .findAllComponents({ name: 'Draggable' })
    .filter(draggable => draggable.props('handle') === '.card-drag-handle');

const findAddItemButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-add-item-button"]');

const findAddItemPicker = wrapper =>
  wrapper.findComponent({ name: 'KanbanOpportunityPicker' });

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

  it('refetches the current board after a manual opportunity is created', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');
    KanbanBoardsAPI.show.mockClear();

    await findAddItemPicker(wrapper).vm.$emit('created');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10);
  });

  it('opens the manual picker for every board', async () => {
    const wrapper = await mountView();

    await findAddItemButtons(wrapper)[0].trigger('click');

    expect(findAddItemPicker(wrapper).exists()).toBe(true);
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

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
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

    expect(KanbanBoardsAPI.reorderCardById).toHaveBeenCalledWith(10, 501, {
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

    expect(KanbanBoardsAPI.deleteCardById).toHaveBeenCalledWith(10, 501);
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

  it('refetches board on modal updated event', async () => {
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
    modal.vm.$emit('updated');
    await flushPromises();

    expect(KanbanBoardsAPI.show).toHaveBeenCalledWith(10);
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

  it('sends automation configuration when saving', async () => {
    KanbanBoardsAPI.update.mockResolvedValue({
      data: {
        id: 10,
        name: 'Sales Board',
        description: '',
        auto_create_cards_from_conversations: false,
      },
    });
    const wrapper = await mountView();

    await startBoardEdit(wrapper);
    await findAutoCreateToggle(wrapper).setValue(false);
    await findBoardEditForm(wrapper).trigger('submit.prevent');
    await flushPromises();

    expect(KanbanBoardsAPI.update).toHaveBeenCalledWith(10, {
      kanban_board: {
        name: 'Sales Board',
        description: '',
        auto_create_cards_from_conversations: false,
      },
    });
  });

  it('does not allow boards without stages to enable automation', async () => {
    const wrapper = await mountView(
      buildBoardResponse([], {
        auto_create_cards_from_conversations: false,
        stages: [],
      })
    );

    await startBoardEdit(wrapper);

    expect(findAutoCreateToggle(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('KANBAN.BOARD_FORM.NO_STAGES_HELP');
  });

  it('keeps existing board edit behavior working', async () => {
    KanbanBoardsAPI.update.mockResolvedValue({
      data: {
        id: 10,
        name: 'Updated Sales Board',
        description: 'Updated description',
        auto_create_cards_from_conversations: true,
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
      },
    });
  });
});
