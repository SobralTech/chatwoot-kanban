import { mount } from '@vue/test-utils';
import { computed } from 'vue';

import KanbanConversationCardItem from '../KanbanConversationCardItem.vue';
import { useMapGetter } from 'dashboard/composables/store';
import kanbanLocale from 'dashboard/i18n/locale/en/kanban.json';
import conversationLocale from 'dashboard/i18n/locale/en/conversation.json';
import contactLocale from 'dashboard/i18n/locale/en/contact.json';

// Resolve against the real locale files: a hand written dictionary here would
// happily translate keys that do not exist in en.json.
const localeMessages = {
  ...kanbanLocale,
  ...conversationLocale,
  ...contactLocale,
};
const translate = (key, values = {}) => {
  const message = key
    .split('.')
    .reduce((node, part) => (node == null ? node : node[part]), localeMessages);
  if (typeof message !== 'string') {
    throw new Error(`Missing translation for ${key}`);
  }

  return Object.entries(values).reduce(
    (text, [name, value]) => text.replaceAll(`{${name}}`, String(value)),
    message
  );
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, values) => translate(key, values) }),
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

  it('shows only regular stages in the stage select', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .get('[data-testid="kanban-stage-select-trigger"]')
      .trigger('click');

    const options = wrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .findAll('[data-testid="kanban-stage-select-option"]')
      .map(option => option.text());

    expect(options).toEqual(['Qualified', 'Proposal']);
    expect(options.join(' ')).not.toContain('Won');
    expect(options.join(' ')).not.toContain('Lost');
  });

  it('emits the picked numeric stage id from the stage select', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-stage"]')
      .get('[data-testid="kanban-stage-select-trigger"]')
      .trigger('click');
    await wrapper
      .findAll('[data-testid="kanban-stage-select-option"]')[1]
      .trigger('click');

    expect(wrapper.emitted('updateStage')?.[0]).toEqual([card, 25]);
  });

  it('opens details from the subject and keyboard-focused card', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-subject"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="kanban-conversation-card"]')
      .trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('openDetails')).toEqual([[card], [card]]);
  });

  it('opens the move dialog from the funnel name and actions menu', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-board"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="kanban-conversation-card-actions"]')
      .trigger('click');
    await wrapper
      .findAll('[data-testid="kanban-conversation-card-actions-menu"] button')
      .find(button => button.text().includes('Move to another funnel'))
      .trigger('click');

    expect(wrapper.emitted('openMove')).toEqual([[card], [card]]);
  });

  it('points out that the funnel can be changed', () => {
    const wrapper = mountItem();

    expect(
      wrapper.get('[data-testid="kanban-conversation-card-board"] i').classes()
    ).toContain('i-lucide-chevron-down');
  });

  it('renders label chips under the subject with an overflow counter', () => {
    const wrapper = mountItem({
      labels: [
        { id: 1, title: 'vip', color: '#ff0000' },
        { id: 2, title: 'billing' },
        { id: 3, title: 'urgent' },
        { id: 4, title: 'renewal' },
      ],
    });

    expect(
      wrapper
        .findAll('[data-testid="kanban-conversation-card-label"]')
        .map(chip => chip.text())
    ).toEqual(['vip', 'billing', 'urgent']);
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-labels"]').text()
    ).toContain('+1');
  });

  it('drops the label row when the card has none', () => {
    const wrapper = mountItem();

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-labels"]').exists()
    ).toBe(false);
  });
});
