import { shallowMount } from '@vue/test-utils';
import KanbanConversationCard from '../KanbanConversationCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => {
      const translations = {
        'KANBAN.CARD.CONVERSATION_ID': `#${values.id}`,
        'KANBAN.CARD.NO_LINKED_CONVERSATION': 'No linked conversation',
        'KANBAN.CARD.EDIT': 'Edit card',
        'KANBAN.CARD.DELETE': 'Delete card',
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

const buildCard = overrides => ({
  id: 10,
  kanbanStageId: 1,
  conversationId: 42,
  subject: 'Enterprise expansion',
  dueAt: '2026-06-11T15:00:00.000Z',
  stageEnteredAt: '2026-06-10T10:00:00.000Z',
  priority: 'high',
  contact: {
    id: 7,
    name: 'Jane Doe',
    thumbnail: 'https://example.com/jane.png',
  },
  inbox: { id: 5, name: 'Support Inbox', channelType: 'Channel::Email' },
  assignee: {
    id: 8,
    name: 'Agent Smith',
    avatarUrl: 'https://example.com/agent.png',
  },
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
    dueAt: null,
    priority: null,
    assignee: null,
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
        Avatar: {
          name: 'Avatar',
          props: ['name', 'src', 'size'],
          template: '<span class="avatar-stub" :title="name">{{ name }}</span>',
        },
        ChannelIcon: {
          name: 'ChannelIcon',
          props: ['inbox'],
          template: '<span class="channel-icon-stub" :title="inbox.name" />',
        },
      },
    },
  });

describe('KanbanConversationCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-10T12:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders an existing conversation card', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Enterprise expansion');
    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.text()).toContain('Support Inbox');
    expect(wrapper.text()).toContain('Agent Smith');
    expect(wrapper.text()).toContain('2h');
  });

  it('shows the native priority indicator when priority is present', () => {
    const wrapper = mountCard();
    const priorityIcon = wrapper.findComponent({ name: 'CardPriorityIcon' });

    expect(priorityIcon.exists()).toBe(true);
    expect(priorityIcon.props('priority')).toBe('high');
    expect(wrapper.find('[data-testid="priority-indicator"]').exists()).toBe(
      true
    );
  });

  it.each(['urgent', 'high', 'medium', 'low'])(
    'uses the native priority indicator for %s priority',
    priority => {
      const wrapper = mountCard({
        card: buildCard({
          priority,
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
        priority: null,
        conversation: {
          ...buildCard().conversation,
          priority: null,
        },
      }),
    });

    expect(wrapper.findComponent({ name: 'CardPriorityIcon' }).exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="priority-indicator"]').exists()).toBe(
      false
    );
  });

  it('does not render the priority indicator for unexpected priority values', () => {
    const wrapper = mountCard({
      card: buildCard({
        priority: 'critical',
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

  it('emits openConversation when the card surface is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0][0]).toEqual(card);
    expect(wrapper.emitted('openDetails')).toBeUndefined();
  });

  it('does not emit openConversation when pointer movement turns the click into a drag', async () => {
    const wrapper = mountCard();
    const card = wrapper.find('article');

    card.element.dispatchEvent(
      new MouseEvent('pointerdown', {
        bubbles: true,
        clientX: 10,
        clientY: 10,
      })
    );
    card.element.dispatchEvent(
      new MouseEvent('pointermove', {
        bubbles: true,
        clientX: 20,
        clientY: 10,
      })
    );
    await card.trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toBeUndefined();
  });

  it('does not emit openConversation when card surface has no conversation', async () => {
    const wrapper = mountCard({ card: buildManualCard() });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toBeUndefined();
  });

  it('emits openConversation when contact avatar is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="contact-avatar"]').trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0][0]).toEqual(card);
    expect(wrapper.emitted('openDetails')).toBeUndefined();
  });

  it('renders subject above contact name when subject is present', () => {
    const wrapper = mountCard();
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
    expect(wrapper.text()).toContain('Sales Inbox');
    expect(wrapper.findComponent({ name: 'CardPriorityIcon' }).exists()).toBe(
      false
    );
  });

  it('renders hover actions for edit and delete', () => {
    const wrapper = mountCard();
    const actions = wrapper.find('[data-testid="kanban-card-hover-actions"]');
    const editButton = wrapper.find('[data-testid="kanban-card-edit"]');
    const deleteButton = wrapper.find('[data-testid="kanban-card-delete"]');

    expect(actions.exists()).toBe(true);
    expect(actions.classes()).toEqual(
      expect.arrayContaining([
        'opacity-0',
        'pointer-events-none',
        'group-hover:opacity-100',
        'group-focus-within:opacity-100',
      ])
    );
    expect(editButton.classes()).toContain('pointer-events-auto');
    expect(deleteButton.classes()).toContain('pointer-events-auto');
    expect(editButton.attributes('title')).toBe('Edit card');
    expect(editButton.attributes('aria-label')).toBe('Edit card');
    expect(deleteButton.attributes('title')).toBe('Delete card');
    expect(deleteButton.attributes('aria-label')).toBe('Delete card');
  });

  it('emits openDetails when edit action is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-edit"]').trigger('click');

    expect(wrapper.emitted('openDetails')).toHaveLength(1);
    expect(wrapper.emitted('openDetails')[0][0]).toEqual(card);
    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  it('emits removeCard when delete action is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-delete"]').trigger('click');

    expect(wrapper.emitted('removeCard')).toHaveLength(1);
    expect(wrapper.emitted('removeCard')[0][0]).toEqual(card);
    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  it('does not emit openConversation when manual card avatar is clicked', async () => {
    const wrapper = mountCard({ card: buildManualCard() });

    await wrapper.find('[data-testid="contact-avatar"]').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toBeUndefined();
    expect(wrapper.find('[data-testid="contact-avatar"]').classes()).toContain(
      'cursor-default'
    );
  });

  it('does not render inline Contact Notes UI', () => {
    const wrapper = mountCard();

    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Show notes');
    expect(wrapper.text()).not.toContain('Hide notes');
  });

  it('renders contact and assignee avatars when assignee exists', () => {
    const wrapper = mountCard();
    const avatars = wrapper.findAllComponents({ name: 'Avatar' });

    expect(avatars).toHaveLength(2);
    expect(avatars[0].props()).toMatchObject({
      name: 'Jane Doe',
      src: 'https://example.com/jane.png',
      size: 28,
    });
    expect(avatars[1].props()).toMatchObject({
      name: 'Agent Smith',
      src: 'https://example.com/agent.png',
      size: 18,
    });
  });

  it('does not leave an assignee slot when assignee is missing', () => {
    const wrapper = mountCard({
      card: buildCard({
        assignee: null,
        conversation: {
          ...buildCard().conversation,
          meta: { ...buildCard().conversation.meta, assignee: null },
        },
      }),
    });

    expect(wrapper.findAllComponents({ name: 'Avatar' })).toHaveLength(1);
    expect(wrapper.text()).not.toContain('Agent Smith');
  });

  it('renders inbox as a compact pill', () => {
    const wrapper = mountCard();
    const pill = wrapper.find('[data-testid="inbox-pill"]');

    expect(pill.text()).toBe('Support Inbox');
    expect(pill.findComponent({ name: 'ChannelIcon' }).exists()).toBe(false);
    expect(pill.classes()).toEqual(
      expect.arrayContaining(['rounded-md', 'bg-n-alpha-2'])
    );
  });

  it('renders the inbox badge over the contact avatar', () => {
    const wrapper = mountCard();
    const avatar = wrapper.find('[data-testid="contact-avatar"]');
    const badge = avatar.find('[data-testid="inbox-avatar-badge"]');

    expect(badge.exists()).toBe(true);
    expect(badge.findComponent({ name: 'ChannelIcon' }).props('inbox')).toEqual(
      expect.objectContaining({ name: 'Support Inbox' })
    );
    expect(avatar.classes()).toContain('relative');
    expect(badge.classes()).toEqual(
      expect.arrayContaining(['absolute', '-bottom-0.5', '-right-0.5'])
    );
  });

  it('renders due date only when dueAt exists', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Jun 11');

    const withoutDueAt = mountCard({ card: buildCard({ dueAt: null }) });

    expect(withoutDueAt.text()).not.toContain('Jun 11');
  });

  it.each([
    ['2026-06-10T11:55:00.000Z', '5m'],
    ['2026-06-10T10:00:00.000Z', '2h'],
    ['2026-06-07T12:00:00.000Z', '3d'],
  ])('formats stage duration for %s as %s', (stageEnteredAt, duration) => {
    const wrapper = mountCard({ card: buildCard({ stageEnteredAt }) });

    expect(wrapper.text()).toContain(duration);
  });

  it('adds titles to long subject and contact text', () => {
    const longSubject = 'Very long enterprise renewal opportunity title';
    const longContactName = 'Very Long Contact Name Incorporated';
    const wrapper = mountCard({
      card: buildCard({
        subject: longSubject,
        contact: { ...buildCard().contact, name: longContactName },
      }),
    });

    expect(wrapper.find('h4').attributes('title')).toBe(longSubject);
    expect(
      wrapper.find('span[title="Very Long Contact Name Incorporated"]').exists()
    ).toBe(true);
  });
});
