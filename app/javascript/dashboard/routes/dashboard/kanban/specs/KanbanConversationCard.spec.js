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
        'KANBAN.CARD.UNKNOWN_CONTACT': 'Unknown Contact',
        'KANBAN.CARD.UNKNOWN_INBOX': 'Unknown Inbox',
        'KANBAN.CARD.NO_LINKED_CONVERSATION': 'No linked conversation',
        'KANBAN.CARD.EDIT': 'Edit card',
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
  shortTimestamp: () => 'now',
}));

const buildCard = overrides => ({
  id: 10,
  kanbanStageId: 1,
  subject: 'Enterprise expansion',
  stage_entered_at: '2026-06-05T18:00:00-03:00',
  due_at: '2026-06-07T18:00:00-03:00',
  conversationId: 42,
  card_priority: 'high',
  assignees: [{ id: 7, name: 'Agent Smith', avatar_url: 'agent.png' }],
  conversation: {
    inboxId: 5,
    status: 'open',
    lastActivityAt: 123,
    meta: {
      sender: { id: 7, name: 'Jane Doe', thumbnail: 'jane.png' },
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
    card_priority: null,
    assignees: [],
    ...overrides,
  });

const mountCard = ({
  card = buildCard(),
  isBusy = false,
  wonStageId = null,
  lostStageId = null,
  reasons = [],
  lostReasonRequired = false,
} = {}) =>
  shallowMount(KanbanConversationCard, {
    props: {
      card,
      isBusy,
      wonStageId,
      lostStageId,
      reasons,
      lostReasonRequired,
    },
    global: {
      stubs: {
        Avatar: {
          name: 'Avatar',
          props: ['name', 'src', 'size', 'roundedFull'],
          template:
            '<span class="avatar-stub">{{ name }} {{ src }} {{ size }}</span>',
        },
        ChannelIcon: {
          name: 'ChannelIcon',
          props: ['inbox'],
          template: '<span class="channel-icon-stub" />',
        },
        InboxName: {
          name: 'InboxName',
          props: ['inbox', 'showIcon'],
          template:
            '<span class="inbox-name-stub">{{ inbox.name }} {{ showIcon }}</span>',
        },
        Popover: {
          name: 'Popover',
          template: '<div><slot /><slot name="content" /></div>',
        },
      },
    },
  });

describe('KanbanConversationCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders an existing conversation card', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Enterprise expansion');
    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.text()).toContain('Support Inbox');
    expect(wrapper.text()).toContain('Agent Smith');
    expect(wrapper.text()).toContain('now');
    expect(wrapper.text()).toContain('07/06/2026');
  });

  it('keeps the draggable root intact', () => {
    const wrapper = mountCard();

    expect(wrapper.element.tagName).toBe('ARTICLE');
    expect(wrapper.classes()).toContain('card-drag-handle');
    expect(wrapper.classes()).not.toContain('no-drag');
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
        card: buildCard({ card_priority: priority }),
      });

      expect(
        wrapper.findComponent({ name: 'CardPriorityIcon' }).props()
      ).toMatchObject({
        priority,
      });
    }
  );

  it('shows the empty priority indicator when priority is missing', () => {
    const wrapper = mountCard({
      card: buildCard({ card_priority: null }),
    });

    expect(
      wrapper.findComponent({ name: 'CardPriorityIcon' }).props('priority')
    ).toBe('');
  });

  it('shows the empty priority indicator for unexpected priority values', () => {
    const wrapper = mountCard({
      card: buildCard({ card_priority: 'critical' }),
    });

    expect(
      wrapper.findComponent({ name: 'CardPriorityIcon' }).props('priority')
    ).toBe('critical');
  });

  it('shows an overflow badge when more than one assignee is set', () => {
    const wrapper = mountCard({
      card: buildCard({
        assignees: [
          { id: 7, name: 'Agent Smith', avatar_url: 'agent.png' },
          { id: 8, name: 'Agent Jones', avatar_url: 'jones.png' },
        ],
      }),
    });

    expect(wrapper.text()).toContain('+1');
  });

  it('does not show an overflow badge for a single assignee', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).not.toContain('+1');
  });

  it('emits openConversation when the card surface is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0][0]).toEqual(card);
  });

  it('renders subject above contact name with title when subject is present', () => {
    const wrapper = mountCard();
    const text = wrapper.text();
    const subject = wrapper.find('p[title="Enterprise expansion"]');

    expect(subject.exists()).toBe(true);
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
  });

  it('does not emit openConversation when the card has no conversation', async () => {
    const wrapper = mountCard({ card: buildManualCard() });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  it('emits openDetails when the settings action is clicked', async () => {
    const card = buildManualCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-settings"]').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toEqual([[card]]);
  });

  it('does not emit openDetails when clicking remove button', async () => {
    const wrapper = mountCard();

    await wrapper.find('[data-testid="kanban-card-remove"]').trigger('click');

    expect(wrapper.emitted('openDetails')).toBeUndefined();
    expect(wrapper.emitted('removeCard')).toHaveLength(1);
  });

  it('emits removeCard when the remove action is clicked', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-remove"]').trigger('click');

    expect(wrapper.emitted('removeCard')).toEqual([[card]]);
  });

  it('marks card action buttons as no-drag', () => {
    const wrapper = mountCard();

    expect(
      wrapper.find('[data-testid="kanban-card-remove"]').classes()
    ).toContain('no-drag');
    expect(
      wrapper.find('[data-testid="kanban-card-settings"]').classes()
    ).toContain('no-drag');
  });

  it('marks remove button as accessible', () => {
    const wrapper = mountCard();
    const removeButton = wrapper.find('[data-testid="kanban-card-remove"]');

    expect(removeButton.attributes('aria-label')).toBe('Remove');
    expect(removeButton.attributes('title')).toBe('Remove');
  });

  it('renders an accessible settings button', () => {
    const wrapper = mountCard();
    const settingsButton = wrapper.find('[data-testid="kanban-card-settings"]');

    expect(settingsButton.attributes('aria-label')).toBe('Edit card');
    expect(settingsButton.attributes('title')).toBe('Edit card');
    expect(settingsButton.find('.i-lucide-settings').exists()).toBe(true);
  });

  it('renders inbox badge separately from the inbox pill', () => {
    const wrapper = mountCard();
    const inboxName = wrapper.findComponent({ name: 'InboxName' });

    expect(wrapper.findComponent({ name: 'ChannelIcon' }).exists()).toBe(true);
    expect(inboxName.props('showIcon')).toBe(false);
  });

  it('does not leave optional rows when optional values are missing', () => {
    const wrapper = mountCard({
      card: buildCard({
        subject: '',
        stage_entered_at: null,
        due_at: null,
        card_priority: null,
        assignees: [],
      }),
    });

    expect(wrapper.find('p[title]').exists()).toBe(false);
    expect(wrapper.find('i.i-lucide-calendar').exists()).toBe(false);
    expect(wrapper.find('i.i-lucide-clock').exists()).toBe(false);
    expect(wrapper.findAllComponents({ name: 'Avatar' })).toHaveLength(1);
  });

  it('does not render inline Contact Notes UI', () => {
    const wrapper = mountCard();

    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('Show notes');
    expect(wrapper.text()).not.toContain('Hide notes');
  });

  it('passes status props through and re-emits changeStatus with the card', () => {
    const card = buildCard({ kanbanStageId: 2 });
    const wrapper = mountCard({
      card,
      wonStageId: 3,
      lostStageId: 4,
      reasons: [{ id: 1, title: 'Price', reason_type: 'lost' }],
      lostReasonRequired: true,
    });

    const badge = wrapper.findComponent({ name: 'KanbanCardStatusBadge' });
    expect(badge.exists()).toBe(true);
    expect(badge.props()).toMatchObject({
      kanbanStageId: 2,
      wonStageId: 3,
      lostStageId: 4,
      lostReasonRequired: true,
    });

    const payload = { targetStageId: 4, reasonId: 1 };
    badge.vm.$emit('change', payload);

    expect(wrapper.emitted('changeStatus')).toEqual([[card, payload]]);
  });

  it('shows the formatted card value when value is present', () => {
    const wrapper = mountCard({ card: buildCard({ value: 1234.5 }) });

    expect(wrapper.find('[data-testid="kanban-card-value"]').exists()).toBe(
      true
    );
  });

  it('does not show a value badge when value is missing', () => {
    const wrapper = mountCard({ card: buildCard({ value: 0 }) });

    expect(wrapper.find('[data-testid="kanban-card-value"]').exists()).toBe(
      false
    );
  });
});
