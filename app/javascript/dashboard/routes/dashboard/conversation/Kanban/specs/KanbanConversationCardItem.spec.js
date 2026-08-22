import { mount } from '@vue/test-utils';
import { computed } from 'vue';

import KanbanConversationCardItem from '../KanbanConversationCardItem.vue';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      Object.entries(values).reduce(
        (message, [name, value]) =>
          message.replaceAll(`{${name}}`, String(value)),
        {
          'KANBAN.CARD.UNKNOWN_BOARD': 'Unknown funnel',
          'KANBAN.CARD.UNKNOWN_STAGE': 'Unknown stage',
          'KANBAN.CARD.CARD_ID': '#{id}',
          'KANBAN.CARD.ACTIONS_MENU': 'Card actions',
          'KANBAN.CARD.MOVE_TO_STAGE': 'Move to stage',
          'KANBAN.CARD.CHANGE_PRIORITY': 'Change priority',
          'KANBAN.CARD.DUE_DATE': 'Due date',
          'KANBAN.CARD.COPY_CARD_ID': 'Copy card ID',
          'KANBAN.CARD.ASSIGN_TO': 'Assign to',
          'KANBAN.CARD.NO_ASSIGNABLE_USERS': 'No agents available',
          'KANBAN.CARD.SLA_STALE': 'Stalled',
          'KANBAN.CARD.SLA_TOOLTIP': 'In this stage for {age} · limit {hours}h',
          'KANBAN.ACTIONS.REMOVE_CARD': 'Delete opportunity',
          'KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED': 'Card ID copied',
          'KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE': 'Clear due date',
          'CONVERSATION.PRIORITY.OPTIONS.NONE': 'No priority',
          'CONVERSATION.PRIORITY.OPTIONS.URGENT': 'Urgent',
          'CONVERSATION.PRIORITY.OPTIONS.HIGH': 'High',
          'CONVERSATION.PRIORITY.OPTIONS.MEDIUM': 'Medium',
          'CONVERSATION.PRIORITY.OPTIONS.LOW': 'Low',
          'CONTACT_PANEL.LABELS.LABEL_SELECT.TITLE': 'Labels',
          'CONVERSATION_SIDEBAR.KANBAN.SET_DUE_DATE': 'Set due date',
          'CONVERSATION_SIDEBAR.KANBAN.LABELS': 'Labels',
          'CONVERSATION_SIDEBAR.KANBAN.IN_STAGE_FOR': '{age} in this stage',
          'KANBAN.OVERVIEW.EXTRA_COUNT': '+{count}',
        }[key] || key
      ),
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

vi.mock('dashboard/composables/useSlaClock', () => ({
  useSlaClock: () => ({ value: Date.now() }),
}));

const popoverStub = {
  name: 'Popover',
  methods: {
    show: vi.fn(),
    hide: vi.fn(),
  },
  template: `
    <div>
      <slot />
      <slot name="content" :hide="hide" />
    </div>
  `,
};

const statusBadgeStub = {
  name: 'KanbanCardStatusBadge',
  emits: ['change'],
  template: `
    <button type="button" data-testid="status-badge" @click="$emit('change', { targetStageId: 30 })">
      status
    </button>
  `,
};

const cardPriorityIconStub = {
  name: 'CardPriorityIcon',
  template: '<span data-testid="priority-icon" />',
};

const avatarStub = {
  name: 'Avatar',
  template: '<span data-testid="avatar" />',
};

const labelDropdownStub = {
  name: 'LabelDropdown',
  template: '<div data-testid="label-dropdown" />',
};

const card = {
  id: 123,
  subject: 'Maria - Sales Inbox',
  value: '125.50',
  priority: 'high',
  stageEnteredAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
  kanbanBoardId: 10,
  kanbanStageId: 20,
  kanbanBoard: {
    id: 10,
    name: 'Sales',
    wonStageId: 30,
    lostStageId: 40,
    lostReasonRequired: true,
    reasons: [{ id: 7, title: 'Budget' }],
  },
  kanbanStage: {
    id: 20,
    name: 'Qualified',
    slaHours: 1,
  },
  labels: [],
  assignees: [],
};

const mountItem = (overrides = {}) =>
  mount(KanbanConversationCardItem, {
    props: {
      card: { ...card, ...overrides },
      board: card.kanbanBoard,
      regularStages: [
        { id: 20, name: 'Qualified' },
        { id: 25, name: 'Proposal' },
      ],
    },
    global: {
      stubs: {
        Popover: popoverStub,
        KanbanCardStatusBadge: statusBadgeStub,
        CardPriorityIcon: cardPriorityIconStub,
        Avatar: avatarStub,
        LabelDropdown: labelDropdownStub,
      },
    },
  });

describe('KanbanConversationCardItem', () => {
  beforeEach(() => {
    useMapGetter.mockReturnValue(computed(() => []));
  });

  it('renders the compact read-only card with value and metadata', () => {
    const wrapper = mountItem();

    expect(
      wrapper.get('[data-testid="kanban-conversation-card-subject"]').text()
    ).toBe('Maria - Sales Inbox');
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-value"]').text()
    ).toContain('125,50');
    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.text()).toContain('Qualified');
    expect(
      wrapper.find('[data-testid="kanban-conversation-card"]').classes()
    ).toContain('border-l-2');
  });

  it('hides the value when the total is zero', () => {
    const wrapper = mountItem({ value: '0.00' });

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-value"]').exists()
    ).toBe(false);
  });

  it('emits field-only priority and status actions', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-priority-option"]')
      .trigger('click');
    await wrapper.get('[data-testid="status-badge"]').trigger('click');

    expect(wrapper.emitted('updatePriority')?.[0]).toEqual([card, '']);
    expect(wrapper.emitted('changeStatus')?.[0]).toEqual([
      card,
      { targetStageId: 30 },
    ]);
  });

  it('shows only regular stages in the stage select', () => {
    const wrapper = mountItem();
    const options = wrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .findAll('option')
      .map(option => option.text());

    expect(options).toEqual(['Qualified', 'Proposal']);
    expect(options).not.toContain('Won');
    expect(options).not.toContain('Lost');
  });
});
