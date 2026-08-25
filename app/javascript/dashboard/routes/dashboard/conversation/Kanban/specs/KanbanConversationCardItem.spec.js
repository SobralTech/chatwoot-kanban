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

// The real Popover hangs its click handler on a wrapper span around the
// trigger slot, so a trigger that stops propagation never opens it. The stub
// above renders both slots unconditionally and cannot see that difference.
const togglingPopoverStub = {
  name: 'Popover',
  data: () => ({ open: false }),
  methods: {
    show() {
      this.open = true;
    },
    hide() {
      this.open = false;
    },
    toggle() {
      this.open = !this.open;
    },
  },
  template: `
    <div>
      <span @click="toggle"><slot /></span>
      <slot v-if="open" name="content" :hide="hide" />
    </div>
  `,
};

const cardPriorityIconStub = {
  name: 'CardPriorityIcon',
  props: ['priority'],
  template: '<span data-testid="priority-icon" />',
};

const avatarStub = {
  name: 'Avatar',
  props: ['name', 'src', 'size', 'roundedFull'],
  template: '<span data-testid="avatar" />',
};

const wootLabelStub = {
  name: 'WootLabel',
  props: ['title', 'color', 'variant', 'small'],
  template:
    '<span data-testid="kanban-conversation-card-label">{{ title }}</span>',
};

const labelDropdownStub = {
  name: 'LabelDropdown',
  props: ['accountLabels', 'selectedLabels', 'allowCreation'],
  template: '<div data-testid="label-dropdown" />',
};

const nestedBoard = { id: 10, name: 'Sales' };
// What the container resolves from the boards list and hands down as `board`:
// the only copy that knows the terminal stages and the reasons.
const fullBoard = {
  ...nestedBoard,
  wonStageId: 30,
  lostStageId: 40,
  lostReasonRequired: true,
  reasons: [{ id: 7, title: 'Budget' }],
};

const card = {
  id: 123,
  subject: 'Maria - Sales Inbox',
  value: '125.50',
  priority: 'high',
  stageEnteredAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
  kanbanBoardId: 10,
  kanbanStageId: 20,
  // _kanban_card.json.jbuilder nests the board's id and name and nothing else.
  kanbanBoard: nestedBoard,
  kanbanStage: {
    id: 20,
    name: 'Qualified',
    slaHours: 1,
  },
  labels: [],
  assignees: [],
};

const mountItem = (overrides = {}, { board = fullBoard, popover } = {}) =>
  mount(KanbanConversationCardItem, {
    props: {
      card: { ...card, ...overrides },
      board,
      regularStages: [
        { id: 20, name: 'Qualified', color: '#25c16b' },
        { id: 25, name: 'Proposal', color: '#1f93ff' },
      ],
    },
    global: {
      stubs: {
        Popover: popover || popoverStub,
        CardPriorityIcon: cardPriorityIconStub,
        Avatar: avatarStub,
        WootLabel: wootLabelStub,
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
    ).toContain('125,5');
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

  it('shows the full value on hover and the compact one inline', () => {
    const wrapper = mountItem({ value: '456465465.56' });
    const value = wrapper.get('[data-testid="kanban-conversation-card-value"]');

    expect(value.text()).toContain('456,5');
    expect(value.attributes('title')).toContain('456.465.465,56');
  });

  it('changes priority through the drill-in menu', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-menu-priority"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="kanban-conversation-card-priority-option"]')
      .trigger('click');

    expect(wrapper.emitted('updatePriority')?.[0]).toEqual([card, '']);
  });

  it('closes the opportunity in one click from the sidebar menu', async () => {
    const wrapper = mountItem();

    await wrapper
      .get('[data-testid="kanban-conversation-card-menu-won"]')
      .trigger('click');

    expect(wrapper.emitted('changeStatus')?.[0]).toEqual([
      card,
      { targetStageId: 30, reasonId: null },
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

  it('keeps a single chevron in the location line, on the stage', () => {
    const wrapper = mountItem();
    const boardButton = wrapper.get(
      '[data-testid="kanban-conversation-card-board"]'
    );
    const stageTrigger = wrapper.get(
      '[data-testid="kanban-conversation-card-stage"]'
    );

    expect(boardButton.find('.i-lucide-chevron-down').exists()).toBe(false);
    expect(stageTrigger.find('.i-lucide-chevron-down').exists()).toBe(true);
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

  it('caps the label row at two chips plus an overflow counter', () => {
    const wrapper = mountItem({
      labels: [
        { id: 1, title: 'vip', color: '#ff0000' },
        { id: 2, title: 'billing' },
        { id: 3, title: 'urgent' },
        { id: 4, title: 'renewal' },
        { id: 5, title: 'a' },
        { id: 6, title: 'b' },
        { id: 7, title: 'c' },
        { id: 8, title: 'd' },
      ],
    });

    expect(
      wrapper
        .findAll('[data-testid="kanban-conversation-card-label"]')
        .map(chip => chip.text())
    ).toEqual(['vip', 'billing']);
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-labels"]').text()
    ).toContain('+6');
  });

  it('edits labels through the menu with the titles the card resolved', async () => {
    const wrapper = mountItem({
      labels: [
        { id: 1, title: 'vip', color: '#ff0000' },
        { id: 2, title: 'billing' },
      ],
    });

    const labelsItem = wrapper.get(
      '[data-testid="kanban-conversation-card-menu-labels"]'
    );
    expect(labelsItem.text()).toContain('2');

    await labelsItem.trigger('click');
    const dropdown = wrapper.getComponent(labelDropdownStub);
    expect(dropdown.props('selectedLabels')).toEqual(['vip', 'billing']);

    dropdown.vm.$emit('add', { title: 'urgent' });
    expect(wrapper.emitted('updateLabels').at(-1)[1]).toEqual([
      'vip',
      'billing',
      'urgent',
    ]);

    dropdown.vm.$emit('remove', 'vip');
    expect(wrapper.emitted('updateLabels').at(-1)[1]).toEqual(['billing']);
  });

  it('drops the people row when there are no labels nor assignees', () => {
    const wrapper = mountItem({ labels: [] });

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-labels"]').exists()
    ).toBe(false);
  });

  it('drops the facts row when all optional facts are empty', () => {
    const wrapper = mountItem({
      value: '0',
      priority: '',
      dueAt: null,
      stageEnteredAt: null,
    });

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-facts"]').exists()
    ).toBe(false);
  });

  it('opens the actions menu from its trigger', async () => {
    const wrapper = mountItem({}, { popover: togglingPopoverStub });
    const menu = '[data-testid="kanban-conversation-card-actions-menu"]';

    expect(wrapper.find(menu).exists()).toBe(false);

    await wrapper
      .get('[data-testid="kanban-conversation-card-actions"]')
      .trigger('click');

    expect(wrapper.find(menu).exists()).toBe(true);
  });

  it('offers the status actions when the board has terminal stages', () => {
    const wrapper = mountItem();

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-won"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-conversation-card-menu-won"]').exists()
    ).toBe(true);
  });

  it('hides the quick close actions on funnels without terminals', () => {
    const wrapper = mountItem({}, { board: { ...nestedBoard, reasons: [] } });

    expect(
      wrapper.find('[data-testid="kanban-conversation-card-won"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="kanban-conversation-card-lost"]').exists()
    ).toBe(false);
  });

  describe('terminal cards', () => {
    const terminalOverrides = {
      kanbanStageId: 40,
      kanbanReasonId: 7,
      dueAt: '2026-12-20T12:00:00.000Z',
    };

    it('replaces the stage line with the status line', () => {
      const wrapper = mountItem(terminalOverrides);
      const statusLine = wrapper.get(
        '[data-testid="kanban-conversation-card-terminal-status"]'
      );

      expect(statusLine.text()).toContain('Lost · Budget');
      expect(
        wrapper.find('[data-testid="kanban-conversation-card-stage"]').exists()
      ).toBe(false);
    });

    it('shows the closing date and hides the due date', () => {
      const wrapper = mountItem(terminalOverrides);

      expect(
        wrapper
          .find('[data-testid="kanban-conversation-card-terminal-status"]')
          .text()
      ).toMatch(/\d{2}\/\d{2}/);
      expect(
        wrapper
          .find('[data-testid="kanban-conversation-card-due-date"]')
          .exists()
      ).toBe(false);
    });

    it('does not render the won and lost quick actions', () => {
      const wrapper = mountItem(terminalOverrides);

      expect(
        wrapper.find('[data-testid="kanban-conversation-card-won"]').exists()
      ).toBe(false);
      expect(
        wrapper.find('[data-testid="kanban-conversation-card-lost"]').exists()
      ).toBe(false);
    });

    it('emits reopen from the status line confirmation', async () => {
      const wrapper = mountItem(terminalOverrides);

      await wrapper
        .get('[data-testid="kanban-card-status-confirm"]')
        .trigger('click');

      expect(wrapper.emitted('changeStatus')?.[0]).toEqual([
        wrapper.props('card'),
        { reopen: true },
      ]);
    });

    it('shows only the status when no reason was recorded', () => {
      const wrapper = mountItem({ ...terminalOverrides, kanbanReasonId: null });
      const statusLine = wrapper.get(
        '[data-testid="kanban-conversation-card-terminal-status"]'
      );

      expect(statusLine.text()).toContain('Lost');
      expect(statusLine.text()).not.toContain('· Budget');
    });
  });
});
