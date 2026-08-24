import { flushPromises, mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

import KanbanCardMoveDialog from '../KanbanCardMoveDialog.vue';
import kanbanLocale from 'dashboard/i18n/locale/en/kanban.json';
import conversationLocale from 'dashboard/i18n/locale/en/conversation.json';

// Resolve against the real locale files: a hand written dictionary here would
// happily translate keys that do not exist in en.json.
const localeMessages = { ...kanbanLocale, ...conversationLocale };
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

const SelectStub = {
  props: ['modelValue', 'options', 'placeholder', 'disabled'],
  emits: ['update:modelValue'],
  template: `
    <select
      :value="modelValue"
      :disabled="disabled"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option
        v-for="option in options"
        :key="option.value"
        :value="option.value"
        :disabled="option.disabled"
      >
        {{ option.label }}
      </option>
    </select>
  `,
};

// The payloads reach both surfaces through camelcaseKeys, so the fixtures use
// the shape the component actually receives.
const sourceBoard = {
  id: 10,
  name: 'Sales',
  inboxScopeMode: 'all_inboxes',
  wonStageId: 90,
  lostStageId: 91,
  customFields: [
    { key: 'segment', fieldType: 'text', multiple: false },
    { key: 'region', fieldType: 'text', multiple: false },
    { key: 'products', fieldType: 'list', multiple: true },
  ],
  reasons: [{ id: 9, title: 'Budget rejected' }],
};
const targetBoard = {
  id: 11,
  name: 'Support',
  inboxScopeMode: 'all_inboxes',
  wonStageId: 190,
  lostStageId: 191,
  stagesSummary: [
    { id: 100, name: 'Triage', active: true },
    { id: 190, name: 'Won', active: true },
    { id: 191, name: 'Lost', active: true },
  ],
  customFields: [{ key: 'segment', fieldType: 'text', multiple: false }],
};
const duplicateBoard = { ...targetBoard, id: 12, name: 'Renewals' };
const incompatibleBoard = {
  ...targetBoard,
  id: 13,
  name: 'Enterprise',
  inboxScopeMode: 'selected_inboxes',
  allowedInboxes: [{ id: 9 }],
};
const card = {
  id: 123,
  kanbanBoardId: 10,
  kanbanStageId: 91,
  kanbanReasonId: 9,
  customFieldKeys: ['segment', 'region', 'products'],
};

const sourceStages = [
  { id: 80, name: 'Qualification', active: true },
  { id: 90, name: 'Won', active: true },
  { id: 91, name: 'Lost', active: true },
];

const mountDialog = (overrides = {}) =>
  mount(KanbanCardMoveDialog, {
    props: {
      card,
      boards: [sourceBoard, targetBoard, duplicateBoard, incompatibleBoard],
      board: sourceBoard,
      stages: sourceStages,
      wonStageId: 90,
      lostStageId: 91,
      inboxId: 5,
      reasons: sourceBoard.reasons,
      ...overrides,
    },
    global: { stubs: { Select: SelectStub } },
  });

const boardSelect = wrapper =>
  wrapper.get('[data-testid="kanban-card-move-dialog-board"]');
const stageButtons = wrapper =>
  wrapper.findAll('[data-testid="kanban-card-move-dialog-stage"]');

describe('KanbanCardMoveDialog', () => {
  it('offers the current funnel when nothing else holds the card', async () => {
    const wrapper = mountDialog({ card: { ...card, kanbanStageId: 80 } });
    const stages = stageButtons(wrapper);

    // Won and Lost never show up as a move target, and the stage the card is
    // already in stays, offered as a reorder to the top.
    expect(stages.map(stage => stage.text())).toEqual([
      'Qualification (current) — move to top',
    ]);

    await stages[0].trigger('click');
    await wrapper
      .get('[data-testid="kanban-card-move-dialog-submit"]')
      .trigger('click');

    expect(wrapper.emitted('move')).toEqual([[{ boardId: 10, stageId: 80 }]]);
  });

  it('disables funnels that already hold a card for the conversation', async () => {
    const wrapper = mountDialog({
      existingCards: [card, { id: 124, kanbanBoardId: 12 }],
    });
    const options = boardSelect(wrapper).findAll('option');

    expect(options.map(option => option.text())).not.toContain('Enterprise');
    expect(options[0].element.disabled).toBe(true);
    expect(options[1].element.disabled).toBe(false);
    expect(options[2].element.disabled).toBe(true);
    expect(options[2].text()).toContain('124');
    expect(
      wrapper.get('[data-testid="kanban-card-move-dialog-taken"]').text()
    ).toContain('123');
    expect(stageButtons(wrapper)).toHaveLength(0);

    await boardSelect(wrapper).setValue('11');
    await flushPromises();

    expect(stageButtons(wrapper).map(stage => stage.text())).toEqual([
      'Triage',
    ]);
  });

  it('lists every consequence of leaving the source funnel', async () => {
    const wrapper = mountDialog({ existingCards: [card] });

    await boardSelect(wrapper).setValue('11');
    await flushPromises();
    await stageButtons(wrapper)[0].trigger('click');

    expect(wrapper.text()).toContain('The opportunity will be reopened.');
    expect(wrapper.text()).toContain(
      'The reason "Budget rejected" will be removed.'
    );
    expect(wrapper.text()).toContain('2 of 3 custom fields');

    await wrapper
      .get('[data-testid="kanban-card-move-dialog-submit"]')
      .trigger('click');

    expect(wrapper.emitted('move')).toEqual([[{ boardId: 11, stageId: 100 }]]);
  });

  it('explains a clean transfer', async () => {
    const compatibleBoard = {
      ...targetBoard,
      customFields: [...sourceBoard.customFields],
    };
    const wrapper = mountDialog({
      card: { ...card, kanbanStageId: 80, kanbanReasonId: null },
      boards: [sourceBoard, compatibleBoard],
    });

    await boardSelect(wrapper).setValue('11');
    await flushPromises();
    await stageButtons(wrapper)[0].trigger('click');

    expect(
      wrapper.get('[data-testid="kanban-card-move-dialog-clean"]').text()
    ).toContain('keeps all its data');
  });

  it('says so when no other funnel is available', () => {
    const wrapper = mountDialog({
      boards: [sourceBoard],
      existingCards: [card],
    });

    expect(
      wrapper.get('[data-testid="kanban-card-move-dialog-no-board"]').exists()
    ).toBe(true);
  });
});
