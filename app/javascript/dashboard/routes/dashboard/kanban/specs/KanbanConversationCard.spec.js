import { shallowMount } from '@vue/test-utils';
import KanbanConversationCard from '../KanbanConversationCard.vue';
import ContactNotesAPI from 'dashboard/api/contactNotes';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      const translations = {
        'KANBAN.CARD.CONVERSATION_ID': `#${values.id}`,
        'KANBAN.CARD.INBOX': `Inbox: ${values.inbox}`,
        'KANBAN.CARD.ASSIGNEE': `Assignee: ${values.assignee}`,
        'KANBAN.CARD.PRIORITY': `Priority: ${values.priority}`,
        'KANBAN.CARD.LAST_ACTIVITY': `Last activity: ${values.time}`,
        'KANBAN.CARD.NO_LINKED_CONVERSATION': 'No linked conversation',
        'KANBAN.NOTES.SHOW': 'Show notes',
        'KANBAN.NOTES.HIDE': 'Hide notes',
        'KANBAN.NOTES.EMPTY': 'No notes yet.',
        'KANBAN.NOTES.ADD': 'Add note',
        'KANBAN.ACTIONS.REMOVE_CARD': 'Remove',
      };

      return translations[key] || key;
    },
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInboxById': () => ({ name: 'Support Inbox' }),
    },
  }),
}));

vi.mock('dashboard/api/contactNotes', () => ({
  default: {
    get: vi.fn(() => Promise.resolve({ data: [] })),
    create: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));

vi.mock('shared/helpers/timeHelper', () => ({
  dynamicTime: () => 'just now',
}));

const buildCard = overrides => ({
  id: 10,
  kanbanStageId: 1,
  conversationId: 42,
  conversation: {
    inboxId: 5,
    status: 'open',
    priority: 'high',
    lastActivityAt: 123,
    meta: {
      sender: { id: 7, name: 'Jane Doe' },
      assignee: { name: 'Agent Smith' },
    },
    messages: [{ content: 'First message' }],
  },
  ...overrides,
});

const buildManualCard = overrides =>
  buildCard({
    subject: 'Renewal follow-up',
    contact: { id: 11, name: 'Manual Contact' },
    inbox: { id: 12, name: 'Sales Inbox' },
    conversationId: null,
    conversation: null,
    ...overrides,
  });

const mountCard = ({ card = buildCard(), activeActionKey = '' } = {}) =>
  shallowMount(KanbanConversationCard, {
    props: {
      card,
      activeActionKey,
    },
    global: {
      stubs: {
        ContactNoteItem: true,
      },
    },
  });

describe('KanbanConversationCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders an existing conversation card', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.text()).toContain('#42');
    expect(wrapper.text()).toContain('First message');
    expect(wrapper.text()).toContain('Inbox: Support Inbox');
    expect(wrapper.text()).toContain('Assignee: Agent Smith');
    expect(wrapper.text()).toContain('Priority: high');
    expect(wrapper.text()).toContain('Last activity: just now');
  });

  it('emits openConversation when the card surface is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0][0]).toEqual(card);
  });

  it('renders subject above contact name when subject is present', () => {
    const wrapper = mountCard({
      card: buildCard({ subject: 'Enterprise expansion' }),
    });
    const text = wrapper.text();

    expect(text).toContain('Enterprise expansion');
    expect(text.indexOf('Enterprise expansion')).toBeLessThan(
      text.indexOf('Jane Doe')
    );
  });

  it('renders manual-like card contact and inbox safely', () => {
    const wrapper = mountCard({ card: buildManualCard() });

    expect(wrapper.text()).toContain('Renewal follow-up');
    expect(wrapper.text()).toContain('Manual Contact');
    expect(wrapper.text()).toContain('Inbox: Sales Inbox');
  });

  it('does not emit openConversation when conversationId is null', async () => {
    const wrapper = mountCard({ card: buildManualCard() });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  it('shows no linked conversation state when conversation is missing', () => {
    const wrapper = mountCard({ card: buildManualCard() });

    expect(wrapper.text()).toContain('No linked conversation');
  });

  it('does not emit openConversation for card controls and notes actions', async () => {
    const wrapper = mountCard();

    await wrapper.find('button[type="button"].text-xs').trigger('click');
    await wrapper.find('button.text-n-ruby-11').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('removeCard')).toHaveLength(1);
  });

  it('emits removeCard when the remove action is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('button.text-n-ruby-11').trigger('click');

    expect(wrapper.emitted('removeCard')).toEqual([[card]]);
  });

  it('marks internal controls as non-draggable', async () => {
    const wrapper = mountCard();

    await wrapper.find('button[type="button"].text-xs').trigger('click');

    expect(wrapper.find('button.text-n-ruby-11').classes()).toContain(
      'no-drag'
    );
    expect(wrapper.find('button[type="button"].text-xs').classes()).toContain(
      'no-drag'
    );
    expect(wrapper.find('textarea').classes()).toContain('no-drag');
    expect(wrapper.find('button[type="submit"]').classes()).toContain(
      'no-drag'
    );
  });

  it('fetches notes when opening notes panel and creates a note', async () => {
    ContactNotesAPI.get.mockResolvedValueOnce({ data: [] });
    ContactNotesAPI.create.mockResolvedValueOnce({
      data: { id: 9, content: 'follow up', user: { name: 'Agent' } },
    });

    const wrapper = mountCard();
    const toggleButton = wrapper.find('button[type="button"].text-xs');
    await toggleButton.trigger('click');
    await Promise.resolve();

    expect(ContactNotesAPI.get).toHaveBeenCalledWith(7);

    const textarea = wrapper.find('textarea');
    await textarea.setValue('follow up');
    await wrapper.find('form').trigger('submit.prevent');
    await Promise.resolve();

    expect(ContactNotesAPI.create).toHaveBeenCalledWith(7, 'follow up');
  });

  it('keeps contact notes available when card contact has an id', async () => {
    ContactNotesAPI.get.mockResolvedValueOnce({ data: [] });

    const wrapper = mountCard({ card: buildManualCard() });
    await wrapper.find('button[type="button"].text-xs').trigger('click');
    await Promise.resolve();

    expect(ContactNotesAPI.get).toHaveBeenCalledWith(11);
    expect(wrapper.find('textarea').exists()).toBe(true);
  });
});
