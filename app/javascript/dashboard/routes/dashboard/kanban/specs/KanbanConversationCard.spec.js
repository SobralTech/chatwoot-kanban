import { nextTick } from 'vue';
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
        'KANBAN.CARD.ACTIONS_MENU': 'Card actions',
        'KANBAN.CARD.MOVE_TO': 'Move to',
        'KANBAN.CARD.ASSIGN_TO': 'Assign to',
        'KANBAN.CARD.OPEN_IN_NEW_TAB': 'Open in a new tab',
        'KANBAN.CARD.NO_REGULAR_STAGES': 'No other stages available.',
        'KANBAN.CARD.NO_ASSIGNABLE_USERS': 'No agents available.',
        'KANBAN.CARD.ASSIGN_SUCCESS': 'Assignees updated.',
        'KANBAN.CARD.ASSIGN_ERROR': 'Could not update the assignees.',
        'KANBAN.CARD.MOVE_SUCCESS': 'Card moved.',
        'KANBAN.CARD.DUE_DATE': 'Due date',
        'KANBAN.CARD.TERMINAL_STAGE_HINT':
          'Use the status badge to mark as won or lost.',
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
  board = {},
  boards = [],
  stages = [],
  assignableUsers = [],
  wonStageId = null,
  lostStageId = null,
  reasons = [],
  lostReasonRequired = false,
} = {}) =>
  shallowMount(KanbanConversationCard, {
    props: {
      card,
      isBusy,
      board,
      boards,
      stages,
      assignableUsers,
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
        // The status rows are the thing under test here, so they render for
        // real instead of collapsing into a shallow stub.
        KanbanStatusMenuItems: false,
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

  it('refuses the drag while one of its own actions is in flight', () => {
    const wrapper = mountCard({ isBusy: true });

    expect(wrapper.classes()).toContain('no-drag');
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

  it('stacks three assignees and shows the remaining count', () => {
    const wrapper = mountCard({
      card: buildCard({
        assignees: [
          { id: 7, name: 'Agent Smith', avatar_url: 'agent.png' },
          { id: 8, name: 'Agent Jones', avatar_url: 'jones.png' },
          { id: 9, name: 'Agent Brown', avatar_url: 'brown.png' },
          { id: 10, name: 'Agent Taylor', avatar_url: 'taylor.png' },
        ],
      }),
    });

    expect(
      wrapper.findAll('[data-testid="kanban-card-assignee"]')
    ).toHaveLength(3);
    expect(
      wrapper.find('[data-testid="kanban-card-assignee-overflow"]').text()
    ).toBe('+1');
  });

  it('does not show an overflow badge for up to three assignees', () => {
    const wrapper = mountCard({
      card: buildCard({
        assignees: [
          { id: 7, name: 'Agent Smith', avatar_url: 'agent.png' },
          { id: 8, name: 'Agent Jones', avatar_url: 'jones.png' },
          { id: 9, name: 'Agent Brown', avatar_url: 'brown.png' },
        ],
      }),
    });

    expect(
      wrapper.findAll('[data-testid="kanban-card-assignee"]')
    ).toHaveLength(3);
    expect(
      wrapper.find('[data-testid="kanban-card-assignee-overflow"]').exists()
    ).toBe(false);
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

  it('opens details when a manual card surface is clicked', async () => {
    const card = buildManualCard();
    const wrapper = mountCard({ card });

    await wrapper.find('article').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toEqual([[card]]);
  });

  it('emits openDetails when the edit menu action is clicked', async () => {
    const card = buildManualCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-edit"]').trigger('click');

    expect(wrapper.emitted('openConversation')).toBeUndefined();
    expect(wrapper.emitted('openDetails')).toEqual([[card]]);
  });
  it('lists regular stages and emits the selected destination', async () => {
    const card = buildCard({ kanbanStageId: 1 });
    const wrapper = mountCard({
      card,
      stages: [
        { id: 1, name: 'Current stage' },
        { id: 2, name: 'Next stage' },
        { id: 3, name: 'Won', color: '#0f0' },
      ],
      wonStageId: 3,
      lostStageId: 4,
    });

    await wrapper.find('[data-testid="kanban-card-move"]').trigger('click');

    const moveOptions = wrapper.findAll(
      '[data-testid="kanban-card-move-stage"]'
    );
    expect(moveOptions).toHaveLength(1);
    expect(moveOptions[0].text()).toContain('Next stage');

    await moveOptions[0].trigger('click');

    expect(wrapper.emitted('moveToStage')).toEqual([[card, 2]]);
  });
  it('filters eligible boards and confirms cross-board moves', async () => {
    const card = buildCard({
      kanbanBoardId: 1,
      inbox: { id: 5, name: 'Sales Inbox' },
      kanbanStageId: 1,
    });
    const sourceBoard = {
      id: 1,
      name: 'Sales',
      position: 2,
      inboxScopeMode: 'all_inboxes',
      wonStageId: 3,
      lostStageId: 4,
      customFields: [],
    };
    const targetBoard = {
      id: 2,
      name: 'Support',
      position: 1,
      inboxScopeMode: 'selected_inboxes',
      allowedInboxIds: [5],
      stagesSummary: [{ id: 10, name: 'Triage', color: '#00f' }],
      customFields: [],
    };
    const blockedBoard = {
      id: 3,
      name: 'Blocked',
      position: 0,
      inboxScopeMode: 'selected_inboxes',
      allowedInboxIds: [99],
      stagesSummary: [{ id: 11, name: 'Other', color: '#000' }],
      customFields: [],
    };
    const wrapper = mountCard({
      card,
      board: sourceBoard,
      boards: [blockedBoard, targetBoard, sourceBoard],
      stages: [
        { id: 1, name: 'Current stage' },
        { id: 2, name: 'Next stage' },
        { id: 3, name: 'Won', color: '#0f0' },
        { id: 4, name: 'Lost', color: '#f00' },
      ],
      wonStageId: 3,
      lostStageId: 4,
    });

    await wrapper.find('[data-testid="kanban-card-move"]').trigger('click');

    const boardSelect = wrapper.findComponent({ name: 'Select' });
    expect(boardSelect.props('options').map(option => option.value)).toEqual([
      1, 2,
    ]);

    await boardSelect.vm.$emit('update:modelValue', 2);
    await nextTick();
    await wrapper
      .find('[data-testid="kanban-card-move-stage"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="kanban-card-move-confirm-clean"]').exists()
    ).toBe(true);
    expect(wrapper.emitted('moveToBoard')).toBeUndefined();

    await wrapper
      .find('[data-testid="kanban-card-move-confirm-submit"]')
      .trigger('click');

    expect(wrapper.emitted('moveToBoard')).toEqual([
      [card, { boardId: 2, stageId: 10 }],
    ]);
  });

  it('toggles an assignee from the assign submenu', async () => {
    const card = buildCard();
    const wrapper = mountCard({
      card,
      assignableUsers: [
        { id: 7, name: 'Agent Smith' },
        { id: 8, name: 'Agent Jones' },
      ],
    });

    await wrapper.find('[data-testid="kanban-card-assign"]').trigger('click');
    const assignOptions = wrapper.findAll(
      '[data-testid="kanban-card-assign-agent"]'
    );
    expect(assignOptions).toHaveLength(2);
    expect(assignOptions[0].find('.i-lucide-check').exists()).toBe(true);

    await assignOptions[1].trigger('click');

    expect(wrapper.emitted('assignAgent')).toEqual([[card, 8]]);
  });

  it('moves priority selection into the actions menu', async () => {
    const wrapper = mountCard();

    await wrapper.find('[data-testid="kanban-card-priority"]').trigger('click');
    const priorityOptions = wrapper.findAll(
      '[data-testid="kanban-card-priority-option"]'
    );
    expect(priorityOptions).toHaveLength(5);

    await priorityOptions[0].trigger('click');

    expect(wrapper.emitted('updatePriority')).toEqual([
      [wrapper.props('card'), ''],
    ]);
  });

  it('emits the picked due date from the actions menu', async () => {
    const card = buildCard();
    const wrapper = mountCard({ card });

    await wrapper.find('[data-testid="kanban-card-due-date"]').trigger('click');
    const picker = wrapper.findComponent({ name: 'KanbanDueDatePicker' });
    expect(picker.props('modelValue')).toBe('2026-06-07');

    picker.vm.$emit('change', '2026-07-01');
    await nextTick();

    expect(wrapper.emitted('updateDueDate')).toEqual([[card, '2026-07-01']]);
  });

  it('disables the menu and shows a spinner while the card is busy', () => {
    const wrapper = mountCard({ isBusy: true });

    const trigger = wrapper.find('[data-testid="kanban-card-actions"]');
    expect(trigger.attributes('disabled')).toBeDefined();
    expect(trigger.find('.i-lucide-loader-circle').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-card-edit"]').attributes('disabled')
    ).toBeDefined();
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

  it('marks the actions trigger as no-drag', () => {
    const wrapper = mountCard();

    expect(
      wrapper.find('[data-testid="kanban-card-actions"]').classes()
    ).toContain('no-drag');
  });

  it('marks remove button as accessible', () => {
    const wrapper = mountCard();
    const removeButton = wrapper.find('[data-testid="kanban-card-remove"]');

    expect(removeButton.attributes('aria-label')).toBe('Remove');
    expect(removeButton.attributes('title')).toBe('Remove');
  });

  it('renders an accessible actions menu trigger', () => {
    const wrapper = mountCard();
    const actionsButton = wrapper.find('[data-testid="kanban-card-actions"]');

    expect(actionsButton.attributes('aria-label')).toBe('Card actions');
    expect(actionsButton.attributes('title')).toBe('Card actions');
    expect(actionsButton.find('.i-lucide-more-vertical').exists()).toBe(true);
    expect(actionsButton.classes()).not.toContain('opacity-0');
    expect(actionsButton.classes()).not.toContain('group-hover:opacity-100');
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

    const meta = wrapper.find('[data-testid="kanban-card-meta"]');

    expect(wrapper.find('p[title]').exists()).toBe(false);
    expect(meta.find('i.i-lucide-calendar').exists()).toBe(false);
    expect(meta.find('i.i-lucide-clock').exists()).toBe(false);
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

  it('offers won, lost, and reopen actions in the menu', async () => {
    const card = buildCard({ kanbanStageId: 1 });
    const wrapper = mountCard({
      card,
      wonStageId: 3,
      lostStageId: 4,
    });

    expect(wrapper.find('[data-testid="kanban-card-won"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="kanban-card-lost"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="kanban-card-reopen"]').exists()).toBe(
      false
    );

    // No won reasons configured: closing as won takes one click.
    await wrapper.find('[data-testid="kanban-card-won"]').trigger('click');
    expect(wrapper.emitted('changeStatus')).toEqual([
      [card, { targetStageId: 3, reasonId: null }],
    ]);
  });

  it('hides the menu status actions on funnels without terminal stages', () => {
    const wrapper = mountCard();

    expect(wrapper.find('[data-testid="kanban-card-won"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="kanban-card-lost"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="kanban-card-reopen"]').exists()).toBe(
      false
    );
  });

  it('asks for the loss reason before closing as lost from the menu', async () => {
    const card = buildCard({ kanbanStageId: 1 });
    const wrapper = mountCard({
      card,
      wonStageId: 3,
      lostStageId: 4,
      reasons: [{ id: 9, title: 'Price', reason_type: 'lost' }],
      lostReasonRequired: true,
    });

    await wrapper.find('[data-testid="kanban-card-lost"]').trigger('click');

    const form = wrapper.findComponent({ name: 'KanbanStatusReasonForm' });
    expect(form.exists()).toBe(true);
    expect(form.props('required')).toBe(true);

    form.vm.$emit('confirm', 9);
    expect(wrapper.emitted('changeStatus')).toEqual([
      [card, { targetStageId: 4, reasonId: 9 }],
    ]);
  });

  it('confirms reopening from the menu for terminal cards', async () => {
    const card = buildCard({ kanbanStageId: 4 });
    const wrapper = mountCard({
      card,
      wonStageId: 3,
      lostStageId: 4,
    });

    expect(wrapper.find('[data-testid="kanban-card-won"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="kanban-card-lost"]').exists()).toBe(
      false
    );

    await wrapper.find('[data-testid="kanban-card-reopen"]').trigger('click');
    wrapper
      .findComponent({ name: 'KanbanStatusReasonForm' })
      .vm.$emit('confirm', null);

    expect(wrapper.emitted('changeStatus')).toEqual([[card, { reopen: true }]]);
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
