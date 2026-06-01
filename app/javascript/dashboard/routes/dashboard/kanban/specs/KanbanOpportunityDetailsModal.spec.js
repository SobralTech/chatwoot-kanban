import { flushPromises, mount } from '@vue/test-utils';
import KanbanOpportunityDetailsModal from '../KanbanOpportunityDetailsModal.vue';
import ContactNotesAPI from 'dashboard/api/contactNotes';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const storeMocks = vi.hoisted(() => ({
  labels: [],
  dispatch: vi.fn(),
}));

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
        'KANBAN.OPPORTUNITY_DETAILS.LABELS': 'Labels',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_LABELS': 'Save labels',
        'KANBAN.OPPORTUNITY_DETAILS.SAVING_LABELS': 'Saving labels...',
        'KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_AVAILABLE': 'No labels available',
        'KANBAN.OPPORTUNITY_DETAILS.LOAD_LABELS_ERROR':
          'Could not load labels.',
        'KANBAN.OPPORTUNITY_DETAILS.SAVE_LABELS_ERROR':
          'Could not save labels.',
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
        'KANBAN.NOTES.TITLE': 'Contact notes',
        'KANBAN.NOTES.LOADING': 'Loading notes...',
        'KANBAN.NOTES.EMPTY': 'No notes yet.',
        'KANBAN.NOTES.NO_CONTACT': 'No contact is linked to this conversation.',
        'KANBAN.NOTES.PLACEHOLDER': 'Add a contact note',
        'KANBAN.NOTES.ADD': 'Add note',
        'KANBAN.NOTES.REFRESH': 'Refresh notes',
        'KANBAN.NOTES.REQUIRED': 'Enter a note before adding it.',
        'KANBAN.NOTES.BOT': 'Bot',
        'KANBAN.NOTES.CREATE_ERROR': 'Could not add the contact note.',
        'KANBAN.NOTES.FETCH_ERROR': 'Could not load contact notes.',
      };

      return translations[key] || key;
    },
  }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    showCardById: vi.fn(),
    updateCardDetailsById: vi.fn(),
    getCardLabels: vi.fn(),
    updateCardLabels: vi.fn(),
  },
}));

vi.mock('dashboard/api/contactNotes', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
  },
}));

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await vi.importActual('vue');

  return {
    useStore: () => ({ dispatch: storeMocks.dispatch }),
    useMapGetter: () => computed(() => storeMocks.labels),
  };
});

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

const contactNoteItemStub = {
  props: ['note', 'writtenBy'],
  template: `
    <article data-testid="kanban-opportunity-note">
      <span>{{ writtenBy }}</span>
      <time v-if="note.createdAt">{{ note.createdAt }}</time>
      <p>{{ note.content }}</p>
    </article>
  `,
};

const buildCard = overrides => ({
  id: 501,
  subject: 'Enterprise expansion',
  startsAt: '2026-06-01T09:00',
  dueAt: '2026-06-05T18:00',
  conversationId: 42,
  contact: { id: 91, name: 'Acme Buyer' },
  ...overrides,
});

const buildNote = overrides => ({
  id: 1,
  content: 'First contact note',
  created_at: 1780304400,
  user: { id: 7, name: 'Jane Agent' },
  ...overrides,
});

const labels = [
  { id: 1, title: 'hot', color: '#ff0000' },
  { id: 2, title: 'enterprise', color: '#00ff00' },
];

const mountModal = async ({
  card = buildCard(),
  resolveLoad = true,
  resolveLabels = true,
  accountLabels = labels,
  assignedLabels = [labels[0]],
  notes = [],
  resolveNotes = true,
} = {}) => {
  storeMocks.labels = accountLabels;
  storeMocks.dispatch.mockResolvedValue();

  if (resolveLabels) {
    KanbanBoardsAPI.getCardLabels.mockResolvedValue({
      data: { payload: assignedLabels },
    });
  }

  if (resolveLoad) {
    KanbanBoardsAPI.showCardById.mockResolvedValue({ data: card });
  }

  if (resolveNotes) {
    ContactNotesAPI.get.mockResolvedValue({ data: notes });
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
        ContactNoteItem: contactNoteItemStub,
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
const labelButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-opportunity-label"]');
const saveLabelsButton = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-save-labels"]');
const noteContentInput = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-note-content"]');
const addNoteButton = wrapper =>
  wrapper.find('[data-testid="kanban-opportunity-add-note"]');

describe('KanbanOpportunityDetailsModal', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeMocks.labels = [];
    ContactNotesAPI.get.mockResolvedValue({ data: [] });
  });

  it('loads detail through showCardById', async () => {
    await mountModal();

    expect(KanbanBoardsAPI.showCardById).toHaveBeenCalledWith(10, 501);
  });

  it('loads notes using card contact ID', async () => {
    await mountModal();

    expect(ContactNotesAPI.get).toHaveBeenCalledWith(91);
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

  it('renders notes loading state', async () => {
    ContactNotesAPI.get.mockReturnValue(new Promise(() => {}));
    const wrapper = await mountModal({ resolveNotes: false });

    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-notes-loading"]').text()
    ).toContain('Loading notes...');
  });

  it('renders notes empty state', async () => {
    const wrapper = await mountModal({ notes: [] });

    expect(
      wrapper.find('[data-testid="kanban-opportunity-notes-empty"]').text()
    ).toContain('No notes yet.');
  });

  it('renders notes returned by API', async () => {
    const wrapper = await mountModal({
      notes: [buildNote({ content: 'Follow up next week' })],
    });

    const note = wrapper.find('[data-testid="kanban-opportunity-note"]');
    expect(note.text()).toContain('Jane Agent');
    expect(note.text()).toContain('1780304400');
    expect(note.text()).toContain('Follow up next week');
  });

  it('renders notes-load error', async () => {
    ContactNotesAPI.get.mockRejectedValue({
      response: { data: { message: 'Notes load failed' } },
    });
    const wrapper = await mountModal({ resolveNotes: false });

    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-notes-load-error"]').text()
    ).toContain('Notes load failed');
  });

  it('rejects blank note locally', async () => {
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('   ');

    expect(addNoteButton(wrapper).attributes('disabled')).toBeDefined();
    expect(ContactNotesAPI.create).not.toHaveBeenCalled();
  });

  it('valid note calls ContactNotesAPI.create', async () => {
    ContactNotesAPI.create.mockResolvedValue({ data: buildNote() });
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('Call buyer');
    await addNoteButton(wrapper).trigger('click');
    await flushPromises();

    expect(ContactNotesAPI.create).toHaveBeenCalledWith(91, 'Call buyer');
  });

  it('submitted note content is trimmed', async () => {
    ContactNotesAPI.create.mockResolvedValue({ data: buildNote() });
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('  Call buyer  ');
    await addNoteButton(wrapper).trigger('click');
    await flushPromises();

    expect(ContactNotesAPI.create).toHaveBeenCalledWith(91, 'Call buyer');
  });

  it('prevents duplicate note submission while pending', async () => {
    ContactNotesAPI.create.mockReturnValue(new Promise(() => {}));
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('Call buyer');
    await addNoteButton(wrapper).trigger('click');

    expect(addNoteButton(wrapper).attributes('disabled')).toBeDefined();

    await addNoteButton(wrapper).trigger('click');
    expect(ContactNotesAPI.create).toHaveBeenCalledTimes(1);
  });

  it('successful submit clears textarea', async () => {
    ContactNotesAPI.create.mockResolvedValue({ data: buildNote() });
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('Call buyer');
    await addNoteButton(wrapper).trigger('click');
    await flushPromises();

    expect(noteContentInput(wrapper).element.value).toBe('');
  });

  it('successful submit updates rendered notes', async () => {
    ContactNotesAPI.create.mockResolvedValue({
      data: buildNote({ content: 'New note' }),
    });
    const wrapper = await mountModal({
      notes: [buildNote({ id: 2, content: 'Existing note' })],
    });

    await noteContentInput(wrapper).setValue('New note');
    await addNoteButton(wrapper).trigger('click');
    await flushPromises();

    const noteTexts = wrapper
      .findAll('[data-testid="kanban-opportunity-note"]')
      .map(note => note.text());
    expect(noteTexts[0]).toContain('New note');
    expect(noteTexts[1]).toContain('Existing note');
  });

  it('renders notes-save error', async () => {
    ContactNotesAPI.create.mockRejectedValue({
      response: { data: { message: 'Notes save failed' } },
    });
    const wrapper = await mountModal();

    await noteContentInput(wrapper).setValue('Call buyer');
    await addNoteButton(wrapper).trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-opportunity-notes-save-error"]').text()
    ).toContain('Notes save failed');
  });

  it('missing contact does not call notes API', async () => {
    const wrapper = await mountModal({ card: buildCard({ contact: null }) });

    expect(ContactNotesAPI.get).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="kanban-opportunity-notes-no-contact"]').text()
    ).toContain('No contact is linked to this conversation.');
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

  it('loads assigned card labels through getCardLabels', async () => {
    await mountModal();

    expect(KanbanBoardsAPI.getCardLabels).toHaveBeenCalledWith(10, 501);
  });

  it('loads available account labels through existing pattern', async () => {
    await mountModal();

    expect(storeMocks.dispatch).toHaveBeenCalledWith('labels/get');
  });

  it('renders label title and color', async () => {
    const wrapper = await mountModal();
    const firstLabel = labelButtons(wrapper)[0];

    expect(firstLabel.text()).toContain('hot');
    expect(firstLabel.find('span').element.style.backgroundColor).toBe(
      'rgb(255, 0, 0)'
    );
  });

  it('marks assigned labels as selected', async () => {
    const wrapper = await mountModal();

    expect(labelButtons(wrapper)[0].attributes('aria-pressed')).toBe('true');
    expect(labelButtons(wrapper)[1].attributes('aria-pressed')).toBe('false');
  });

  it('allows selecting label', async () => {
    const wrapper = await mountModal();

    await labelButtons(wrapper)[1].trigger('click');

    expect(labelButtons(wrapper)[1].attributes('aria-pressed')).toBe('true');
  });

  it('allows deselecting label', async () => {
    const wrapper = await mountModal();

    await labelButtons(wrapper)[0].trigger('click');

    expect(labelButtons(wrapper)[0].attributes('aria-pressed')).toBe('false');
  });

  it('saves full selected-title array through updateCardLabels', async () => {
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: labels },
    });
    const wrapper = await mountModal();

    await labelButtons(wrapper)[1].trigger('click');
    await saveLabelsButton(wrapper).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledWith(10, 501, [
      'hot',
      'enterprise',
    ]);
  });

  it('supports clearing all labels with []', async () => {
    KanbanBoardsAPI.updateCardLabels.mockResolvedValue({
      data: { payload: [] },
    });
    const wrapper = await mountModal();

    await labelButtons(wrapper)[0].trigger('click');
    await saveLabelsButton(wrapper).trigger('click');
    await flushPromises();

    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledWith(10, 501, []);
  });

  it('prevents duplicate label save while pending', async () => {
    KanbanBoardsAPI.updateCardLabels.mockReturnValue(new Promise(() => {}));
    const wrapper = await mountModal();

    await saveLabelsButton(wrapper).trigger('click');

    expect(saveLabelsButton(wrapper).attributes('disabled')).toBeDefined();

    await saveLabelsButton(wrapper).trigger('click');
    expect(KanbanBoardsAPI.updateCardLabels).toHaveBeenCalledTimes(1);
  });

  it('renders labels-loading error', async () => {
    KanbanBoardsAPI.getCardLabels.mockRejectedValue({
      response: { data: { message: 'Labels load failed' } },
    });
    const wrapper = await mountModal({ resolveLabels: false });

    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-labels-load-error"]')
        .text()
    ).toContain('Labels load failed');
  });

  it('renders labels-save error', async () => {
    KanbanBoardsAPI.updateCardLabels.mockRejectedValue({
      response: { data: { message: 'Labels save failed' } },
    });
    const wrapper = await mountModal();

    await saveLabelsButton(wrapper).trigger('click');
    await flushPromises();

    expect(
      wrapper
        .find('[data-testid="kanban-opportunity-labels-save-error"]')
        .text()
    ).toContain('Labels save failed');
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
