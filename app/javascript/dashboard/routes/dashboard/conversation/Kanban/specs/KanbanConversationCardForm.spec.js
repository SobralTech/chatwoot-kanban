import { mount } from '@vue/test-utils';

import KanbanConversationCardForm from '../KanbanConversationCardForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      Object.entries(values).reduce(
        (message, [name, value]) =>
          message.replaceAll(`{${name}}`, String(value)),
        {
          'CONVERSATION_SIDEBAR.KANBAN.NEW_OPPORTUNITY': 'New opportunity',
          'CONVERSATION_SIDEBAR.KANBAN.LOADING': 'Loading',
          'CONVERSATION_SIDEBAR.KANBAN.NO_ELIGIBLE_BOARDS':
            'No funnel accepts this inbox.',
          'CONVERSATION_SIDEBAR.KANBAN.BOARD': 'Funnel',
          'CONVERSATION_SIDEBAR.KANBAN.SELECT_BOARD': 'Select a funnel',
          'CONVERSATION_SIDEBAR.KANBAN.ALREADY_IN_BOARD':
            'This conversation already has #{id} here',
          'CONVERSATION_SIDEBAR.KANBAN.OPEN_EXISTING': 'Open existing',
          'CONVERSATION_SIDEBAR.KANBAN.STAGE': 'Stage',
          'CONVERSATION_SIDEBAR.KANBAN.SELECT_STAGE': 'Select a stage',
          'CONVERSATION_SIDEBAR.KANBAN.SUBJECT': 'Subject',
          'CONVERSATION_SIDEBAR.KANBAN.CANCEL': 'Cancel',
          'CONVERSATION_SIDEBAR.KANBAN.CREATE': 'Create',
          'KANBAN.CARD.NO_REGULAR_STAGES': 'No regular stages',
        }[key] || key
      ),
  }),
}));

const buildStage = (id, name) => ({ id, name, active: true });

const buildBoard = overrides => ({
  id: 10,
  name: 'Sales',
  active: true,
  inboxScopeMode: 'selected_inboxes',
  allowedInboxes: [{ id: 5 }],
  wonStageId: 30,
  lostStageId: 40,
  stagesSummary: [
    buildStage(10, 'New'),
    buildStage(20, 'Qualified'),
    buildStage(30, 'Won'),
    buildStage(40, 'Lost'),
  ],
  ...overrides,
});

const mountForm = props =>
  mount(KanbanConversationCardForm, {
    props,
  });

describe('KanbanConversationCardForm', () => {
  it('preselects one eligible funnel and excludes terminal stages', async () => {
    const wrapper = mountForm({
      boards: [buildBoard()],
      inboxId: 5,
      defaultSubject: 'Maria - Sales Inbox',
    });

    await wrapper.vm.$nextTick();

    expect(
      wrapper.get('[data-testid="kanban-conversation-card-board"]').element
        .value
    ).toBe('10');
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-stage"]').element
        .value
    ).toBe('10');
    expect(
      wrapper
        .get('[data-testid="kanban-conversation-card-stage"]')
        .findAll('option')
        .map(option => option.element.value)
        .filter(Boolean)
    ).toEqual(['10', '20']);
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-subject"]').element
        .value
    ).toBe('Maria - Sales Inbox');
  });

  it('keeps the funnel and stage empty when several funnels are eligible', async () => {
    const wrapper = mountForm({
      boards: [buildBoard(), buildBoard({ id: 11, name: 'Renewals' })],
      inboxId: 5,
      defaultSubject: 'Maria - Sales Inbox',
    });

    await wrapper.vm.$nextTick();

    expect(
      wrapper.get('[data-testid="kanban-conversation-card-board"]').element
        .value
    ).toBe('');
    expect(
      wrapper.get('[data-testid="kanban-conversation-card-stage"]').element
        .value
    ).toBe('');
  });

  it('explains when no funnel accepts the conversation inbox', () => {
    const wrapper = mountForm({
      boards: [buildBoard({ allowedInboxes: [{ id: 99 }] })],
      inboxId: 5,
    });

    expect(
      wrapper
        .find('[data-testid="kanban-conversation-card-no-eligible-boards"]')
        .exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-conversation-card-board"]').exists()
    ).toBe(false);
  });

  it('warns about an existing card and emits the open action', async () => {
    const existingCard = { id: 123, kanbanBoardId: 10 };
    const wrapper = mountForm({
      boards: [buildBoard()],
      cards: [existingCard],
      inboxId: 5,
    });

    await wrapper.vm.$nextTick();
    expect(
      wrapper
        .find('[data-testid="kanban-conversation-card-duplicate-warning"]')
        .exists()
    ).toBe(true);

    await wrapper
      .get('[data-testid="kanban-conversation-card-duplicate-warning"] button')
      .trigger('click');

    expect(wrapper.emitted('open-existing')?.[0][0]).toStrictEqual(
      existingCard
    );
  });

  it('submits only the three conversation-card fields', async () => {
    const wrapper = mountForm({
      boards: [buildBoard()],
      inboxId: 5,
      defaultSubject: 'Maria - Sales Inbox',
    });

    await wrapper.vm.$nextTick();
    await wrapper
      .get('[data-testid="kanban-conversation-card-form"]')
      .trigger('submit');

    expect(wrapper.emitted('create')?.[0][0]).toEqual({
      kanban_board_id: 10,
      kanban_stage_id: 10,
      subject: 'Maria - Sales Inbox',
    });
    expect(wrapper.emitted('create')?.[0][0]).not.toHaveProperty(
      ['starts', 'at'].join('_')
    );
  });

  it('cancels on Escape', async () => {
    const wrapper = mountForm({
      boards: [buildBoard()],
      inboxId: 5,
    });

    await wrapper
      .get('[data-testid="kanban-conversation-card-form"]')
      .trigger('keydown', { key: 'Escape' });

    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });
});
