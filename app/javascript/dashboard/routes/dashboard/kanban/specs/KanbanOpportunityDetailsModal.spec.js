import { flushPromises, mount } from '@vue/test-utils';
import KanbanOpportunityDetailsModal from '../KanbanOpportunityDetailsModal.vue';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => {
      const translations = {
        'KANBAN.OPPORTUNITY_DETAILS.TITLE': 'Opportunity details',
        'KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE': 'Title',
        'KANBAN.OPPORTUNITY_DETAILS.START_DATE': 'Start date',
        'KANBAN.OPPORTUNITY_DETAILS.DUE_DATE': 'Due date',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE': 'Save',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING': 'Saving...',
        'KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION': 'Open conversation',
        'KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION':
          'No linked conversation',
        'KANBAN.OPPORTUNITY_DETAILS.LOADING': 'Loading opportunity details...',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR':
          'Could not load opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR':
          'Could not save opportunity details.',
        'KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE': 'Title is required.',
        'KANBAN.OPPORTUNITY_DETAILS.CLOSE': 'Close opportunity details',
      };

      return translations[key] || key;
    },
  }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    showCardById: vi.fn(),
    updateCardDetailsById: vi.fn(),
  },
}));

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

const buildCard = overrides => ({
  id: 501,
  subject: 'Enterprise expansion',
  startsAt: '2026-06-01T09:00',
  dueAt: '2026-06-05T18:00',
  conversationId: 42,
  ...overrides,
});

const mountModal = async ({ card = buildCard(), resolveLoad = true } = {}) => {
  if (resolveLoad) {
    KanbanBoardsAPI.showCardById.mockResolvedValue({ data: card });
  }

  const wrapper = mount(KanbanOpportunityDetailsModal, {
    props: {
      boardId: 10,
      cardId: 501,
    },
    global: {
      stubs: {
        NextInput: nextInputStub,
        NextButton: nextButtonStub,
        WootModalHeader: {
          props: ['headerTitle'],
          template: '<header>{{ headerTitle }}</header>',
        },
      },
    },
  });

  if (resolveLoad) await flushPromises();

  return wrapper;
};

const subjectInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-subject"]');
const startsAtInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-starts-at"]');
const dueAtInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-due-at"]');
const saveButton = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-save"]');

describe('KanbanOpportunityDetailsModal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('loads detail through showCardById', async () => {
    await mountModal();

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
  });

  it('renders loading state', async () => {
    KanbanBoardsAPI.showCardById.mockReturnValue(new Promise(() => {}));
    const wrapper = mount(KanbanOpportunityDetailsModal, {
      props: {
        boardId: 10,
        cardId: 501,
      },
      global: {
        stubs: {
          NextInput: nextInputStub,
          NextButton: nextButtonStub,
          WootModalHeader: true,
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

  it('renders subject', async () => {
    const wrapper = await mountModal();

    expect(subjectInput(wrapper).element.value).toBe('Enterprise expansion');
  });

  it('renders startsAt and dueAt', async () => {
    const wrapper = await mountModal();

    expect(startsAtInput(wrapper).element.value).toBe('2026-06-01T09:00');
    expect(dueAtInput(wrapper).element.value).toBe('2026-06-05T18:00');
  });

  it('saves trimmed subject', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ subject: 'Renewal' }),
    });
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('  Renewal  ');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ subject: 'Renewal' })
    );
  });

  it('saves optional date values', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard(),
    });
    const wrapper = await mountModal();

    await startsAtInput(wrapper).setValue('2026-06-02T10:30');
    await dueAtInput(wrapper).setValue('2026-06-04T15:45');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({
        starts_at: new Date('2026-06-02T10:30').toISOString(),
        due_at: new Date('2026-06-04T15:45').toISOString(),
      })
    );
  });

  it('clears dates with null', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: buildCard({ startsAt: null, dueAt: null }),
    });
    const wrapper = await mountModal();

    await startsAtInput(wrapper).setValue('');
    await dueAtInput(wrapper).setValue('');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledWith(
      10,
      501,
      expect.objectContaining({ starts_at: null, due_at: null })
    );
  });

  it('rejects blank title locally', async () => {
    const wrapper = await mountModal();

    await subjectInput(wrapper).setValue('   ');
    await wrapper.find('form').trigger('submit');

    expect(KanbanBoardsAPI.updateCardDetailsById).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('Title is required.');
  });

  it('disables save while pending', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockReturnValue(
      new Promise(() => {})
    );
    const wrapper = await mountModal();

    await wrapper.find('form').trigger('submit');

    expect(saveButton(wrapper).attributes('disabled')).toBeDefined();

    await wrapper.find('form').trigger('submit');
    expect(KanbanBoardsAPI.updateCardDetailsById).toHaveBeenCalledTimes(1);
  });

  it('renders backend save error', async () => {
    KanbanBoardsAPI.updateCardDetailsById.mockRejectedValue({
      response: { data: { errors: { subject: ['has already been taken'] } } },
    });
    const wrapper = await mountModal();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-save-error"]').text()
    ).toContain('has already been taken');
  });

  it('emits updated on successful save', async () => {
    const updatedCard = buildCard({ subject: 'Updated opportunity' });
    KanbanBoardsAPI.updateCardDetailsById.mockResolvedValue({
      data: updatedCard,
    });
    const wrapper = await mountModal();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(wrapper.emitted('updated')).toEqual([[updatedCard]]);
  });

  it('renders open conversation action for linked card', async () => {
    const wrapper = await mountModal();

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-open-conversation"]')
        .text()
    ).toContain('Open conversation');
  });

  it('emits open conversation with card payload', async () => {
    const card = buildCard();
    const wrapper = await mountModal({ card });

    await wrapper
      .find('[data-testid="kanban-opportunity-open-conversation"]')
      .trigger('click');

    expect(wrapper.emitted('openConversation')).toEqual([[card]]);
  });

  it('renders no linked conversation for unlinked card', async () => {
    const wrapper = await mountModal({
      card: buildCard({ conversationId: null }),
    });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-no-conversation"]').text()
    ).toContain('No linked conversation');
  });

  it('emits close', async () => {
    const wrapper = await mountModal();

    await wrapper
      .find('[data-testid="kanban-opportunity-close"]')
      .trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
