import { flushPromises, mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

import KanbanConversationMoveDialog from '../KanbanConversationMoveDialog.vue';

const translations = {
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_BOARD': 'Move to another funnel',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_STEPS': 'Move opportunity steps',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_BOARD': '1. Funnel',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_STAGE': '2. Stage',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_STEP_REVIEW': '3. Review',
  'CONVERSATION_SIDEBAR.KANBAN.BOARD': 'Funnel',
  'CONVERSATION_SIDEBAR.KANBAN.STAGE': 'Stage',
  'CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD': 'Select a funnel',
  'CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD':
    'This conversation already has {id} here',
  'CONVERSATION_SIDEBAR.KANBAN.NO_OTHER_BOARDS':
    'No other funnel is available.',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_NEXT': 'Next',
  'CONVERSATION_SIDEBAR.KANBAN.MOVE_BACK': 'Back',
  'KANBAN.OPPORTUNITY_DETAILS.CLOSE_PANEL': 'Close',
  'KANBAN.CARD.NO_REGULAR_STAGES': 'No other stages available.',
  'KANBAN.CARD.MOVE_CONFIRM_CLEAN': 'The opportunity keeps all its data.',
  'KANBAN.CARD.MOVE_CONFIRM_REOPEN': 'The opportunity will be reopened.',
  'KANBAN.CARD.MOVE_CONFIRM_REASON': 'The reason "{reason}" will be removed.',
  'KANBAN.CARD.MOVE_CONFIRM_FIELDS':
    '{count} of {total} custom fields do not exist in {board} and will be discarded: {keys}.',
  'KANBAN.CARD.MOVE_CONFIRM_CANCEL': 'Cancel',
  'KANBAN.CARD.MOVE_CONFIRM_SUBMIT': 'Move',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      Object.entries(values).reduce(
        (message, [name, value]) =>
          message.replaceAll(`{${name}}`, String(value)),
        translations[key] || key
      ),
  }),
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
      <option value="" disabled>{{ placeholder }}</option>
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

const sourceBoard = {
  id: 10,
  name: 'Sales',
  inbox_scope_mode: 'all_inboxes',
  won_stage_id: 90,
  lost_stage_id: 91,
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
  inbox_scope_mode: 'all_inboxes',
  won_stage_id: 190,
  lost_stage_id: 191,
  stages_summary: [
    { id: 100, name: 'Triage', active: true },
    { id: 190, name: 'Won', active: true },
    { id: 191, name: 'Lost', active: true },
  ],
  customFields: [{ key: 'segment', fieldType: 'text', multiple: false }],
};
const duplicateBoard = {
  ...targetBoard,
  id: 12,
  name: 'Renewals',
};
const incompatibleBoard = {
  ...targetBoard,
  id: 13,
  name: 'Enterprise',
  inbox_scope_mode: 'selected_inboxes',
  allowed_inboxes: [{ id: 9 }],
};
const card = {
  id: 123,
  kanban_board: { id: 10, name: 'Sales' },
  kanban_stage: { id: 91, name: 'Lost' },
  kanban_reason_id: 9,
  custom_field_keys: ['segment', 'region', 'products'],
};

const mountDialog = ({ cards = [card], board = sourceBoard } = {}) =>
  mount(KanbanConversationMoveDialog, {
    props: {
      card,
      cards,
      boards: [sourceBoard, targetBoard, duplicateBoard, incompatibleBoard],
      board,
      stages: [
        { id: 80, name: 'Qualification', active: true },
        { id: 90, name: 'Won', active: true },
        { id: 91, name: 'Lost', active: true },
      ],
      wonStageId: 90,
      lostStageId: 91,
      inboxId: 5,
      reasons: sourceBoard.reasons,
    },
    global: { stubs: { Select: SelectStub } },
  });

describe('KanbanConversationMoveDialog', () => {
  it('disables duplicate funnels and excludes inbox-incompatible funnels', async () => {
    const wrapper = mountDialog({
      cards: [card, { id: 124, kanban_board_id: 12 }],
    });
    const options = wrapper
      .find('[data-testid="kanban-conversation-move-dialog-board"]')
      .findAll('option')
      .filter(option => option.attributes('value'));

    expect(options).toHaveLength(3);
    expect(options[1].element.disabled).toBe(false);
    expect(options[2].element.disabled).toBe(true);
    expect(options[2].text()).toContain('124');
    expect(options.map(option => option.text())).not.toContain('Enterprise');

    await wrapper
      .find('[data-testid="kanban-conversation-move-dialog-board"]')
      .setValue('11');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="kanban-conversation-move-dialog-next-board"]')
        .element.disabled
    ).toBe(false);
  });

  it('uses three steps, filters terminal stages and renders all consequences', async () => {
    const wrapper = mountDialog();
    const boardSelect = wrapper.get(
      '[data-testid="kanban-conversation-move-dialog-board"]'
    );

    await boardSelect.setValue('11');
    await wrapper
      .get('[data-testid="kanban-conversation-move-dialog-next-board"]')
      .trigger('click');

    const stages = wrapper.findAll(
      '[data-testid="kanban-conversation-move-dialog-stage"]'
    );
    expect(stages).toHaveLength(1);
    expect(stages[0].text()).toContain('Triage');

    await stages[0].trigger('click');
    expect(wrapper.text()).toContain('The opportunity will be reopened.');
    expect(wrapper.text()).toContain(
      'The reason "Budget rejected" will be removed.'
    );
    expect(wrapper.text()).toContain('2 of 3 custom fields');

    await wrapper
      .get('[data-testid="kanban-conversation-move-dialog-submit"]')
      .trigger('click');
    expect(wrapper.emitted('move')).toEqual([[{ boardId: 11, stageId: 100 }]]);
  });

  it('always explains a clean transfer', async () => {
    const compatibleBoard = {
      ...targetBoard,
      customFields: [...sourceBoard.customFields],
    };
    const wrapper = mount(KanbanConversationMoveDialog, {
      props: {
        card: { ...card, kanban_stage_id: 80, kanban_reason_id: null },
        cards: [card],
        boards: [sourceBoard, compatibleBoard],
        board: sourceBoard,
        stages: [{ id: 80, name: 'Qualification', active: true }],
        wonStageId: 90,
        lostStageId: 91,
        inboxId: 5,
      },
      global: { stubs: { Select: SelectStub } },
    });

    await wrapper
      .get('[data-testid="kanban-conversation-move-dialog-board"]')
      .setValue('11');
    await wrapper
      .get('[data-testid="kanban-conversation-move-dialog-next-board"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="kanban-conversation-move-dialog-stage"]')
      .trigger('click');

    expect(
      wrapper
        .find('[data-testid="kanban-conversation-move-dialog-clean"]')
        .text()
    ).toContain('keeps all its data');
  });
});
