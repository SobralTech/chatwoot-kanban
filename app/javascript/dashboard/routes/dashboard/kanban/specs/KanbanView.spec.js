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
    updateCard: vi.fn(),
    deleteCard: vi.fn(),
  },
}));

const buildBoardResponse = () => ({
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
      cards: [],
    },
  ],
});

const mountView = async () => {
  KanbanBoardsAPI.get.mockResolvedValue({
    data: [{ id: 10, name: 'Sales Board' }],
  });
  KanbanBoardsAPI.show.mockResolvedValue({
    data: buildBoardResponse(),
  });
  KanbanBoardsAPI.reorderStage.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.reorderCard.mockResolvedValue({ data: {} });
  KanbanBoardsAPI.updateCard.mockResolvedValue({ data: {} });

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
    const draggables = wrapper.findAllComponents({ name: 'Draggable' });
    const targetStageCardDraggable = draggables.find(
      draggable =>
        Array.isArray(draggable.props('list')) &&
        draggable.props('list').length === 0 &&
        draggable.props('modelValue').length === 0
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
