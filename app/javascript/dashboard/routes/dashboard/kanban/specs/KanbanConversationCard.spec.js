import { shallowMount } from '@vue/test-utils';
import KanbanConversationCard from '../KanbanConversationCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      const translations = {
        'KANBAN.CARD.CONVERSATION_ID': `#${values.id}`,
        'KANBAN.CARD.INBOX': `Inbox: ${values.inbox}`,
        'KANBAN.CARD.ASSIGNEE': `Assignee: ${values.assignee}`,
        'KANBAN.CARD.LAST_ACTIVITY': `Last activity: ${values.time}`,
        'KANBAN.CARD.NO_LINKED_CONVERSATION': 'No linked conversation',
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
    expect(wrapper.text()).toContain('Last activity: just now');
  });

  it('shows the native priority indicator when priority is present', () => {
    const wrapper = mountCard();
    const priorityIcon = wrapper.findComponent({ name: 'CardPriorityIcon' });

    expect(priorityIcon.exists()).toBe(true);
    expect(priorityIcon.props('priority')).toBe('high');
  });

  it.each(['urgent', 'high', 'medium', 'low'])(
    'uses the native priority indicator for %s priority',
    priority => {
      const wrapper = mountCard({
        card: buildCard({
          conversation: {
            ...buildCard().conversation,
            priority,
          },
        }),
      });

      expect(
        wrapper.findComponent({ name: 'CardPriorityIcon' }).props()
      ).toMatchObject({
        priority,
      });
    }
  );

  it('does not render the priority indicator when priority is missing', () => {
    const wrapper = mountCard({
      card: buildCard({
        conversation: {
          ...buildCard().conversation,
          priority: null,
        },
      }),
    });

    expect(wrapper.findComponent({ name: 'CardPriorityIcon' }).exists()).toBe(
      false
    );
  });

  it('does not render the priority indicator for unexpected priority values', () => {
    const wrapper = mountCard({
      card: buildCard({
        conversation: {
          ...buildCard().conversation,
          priority: 'critical',
        },
      }),
    });

    expect(wrapper.findComponent({ name: 'CardPriorityIcon' }).exists()).toBe(
      false
    );
  });

  it('emits openDetails when the card surface is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openDetails')).toHaveLength(1);
    expect(wrapper.emitted('openDetails')[0][0]).toEqual(card);
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
    expect(wrapper.findComponent({ name: 'CardPriorityIcon' }).exists()).toBe(
      false
    );
  });

  it('emits openDetails even when conversationId is null', async () => {
    const card = buildManualCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openDetails')).toHaveLength(1);
    expect(wrapper.emitted('openDetails')[0][0]).toEqual(card);
  });

  it('shows no linked conversation state when conversation is missing', () => {
    const wrapper = mountCard({ card: buildManualCard() });

    expect(wrapper.text()).toContain('No linked conversation');
  });

  it('does not emit openDetails when clicking remove button', async () => {
    const wrapper = mountCard();

    await wrapper.find('button.text-n-ruby-11').trigger('click');

    expect(wrapper.emitted('openDetails')).toBeUndefined();
    expect(wrapper.emitted('removeCard')).toHaveLength(1);
  });

  it('emits removeCard when the remove action is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('button.text-n-ruby-11').trigger('click');

    expect(wrapper.emitted('removeCard')).toEqual([[card]]);
  });

  it('marks remove button as no-drag', async () => {
    const wrapper = mountCard();

    expect(wrapper.find('button.text-n-ruby-11').classes()).toContain(
      'no-drag'
    );
  });

  it('does not render inline Contact Notes UI', () => {
    const wrapper = mountCard();

    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Show notes');
    expect(wrapper.text()).not.toContain('Hide notes');
  });
});
