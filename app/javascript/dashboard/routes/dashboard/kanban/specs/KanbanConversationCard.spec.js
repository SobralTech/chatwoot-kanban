import { shallowMount } from '@vue/test-utils';
import KanbanConversationCard from '../KanbanConversationCard.vue';
import ContactNotesAPI from 'dashboard/api/contactNotes';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
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

const buildCard = () => ({
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
});

const stages = [
  { id: 1, name: 'Todo' },
  { id: 2, name: 'Doing' },
];

const mountCard = () =>
  shallowMount(KanbanConversationCard, {
    props: {
      card: buildCard(),
      stages,
      activeActionKey: '',
      isFirst: false,
      isLast: false,
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

  it('emits openConversation only when the card header is clicked', async () => {
    const wrapper = mountCard();

    await wrapper
      .find('button[aria-label="KANBAN.CARD.OPEN_CONVERSATION"]')
      .trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
  });

  it('does not emit openConversation for card controls and notes actions', async () => {
    const wrapper = mountCard();

    await wrapper.find('button[type="button"].text-xs').trigger('click');
    await wrapper.find('button.text-n-ruby-11').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('removeCard')).toHaveLength(1);
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
});
