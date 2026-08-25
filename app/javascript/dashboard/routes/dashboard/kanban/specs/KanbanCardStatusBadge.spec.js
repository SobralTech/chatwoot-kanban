import { mount, DOMWrapper } from '@vue/test-utils';
import KanbanCardStatusBadge from '../KanbanCardStatusBadge.vue';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: {} }),
  useMapGetter: () => ({ value: false }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => {
      const translations = {
        'KANBAN.CARD.STATUS.OPEN': 'Open',
        'KANBAN.CARD.STATUS.WON': 'Won',
        'KANBAN.CARD.STATUS.LOST': 'Lost',
        'KANBAN.CARD.STATUS.CHANGE': 'Change status',
        'KANBAN.CARD.STATUS.MARK_AS_WON': 'Mark as won',
        'KANBAN.CARD.STATUS.MARK_AS_LOST': 'Mark as lost',
        'KANBAN.CARD.STATUS.REASON_LABEL': 'Reason',
        'KANBAN.CARD.STATUS.REASON_PLACEHOLDER': 'No reason',
        'KANBAN.CARD.STATUS.REASON_REQUIRED': 'Select a reason to continue.',
        'KANBAN.CARD.STATUS.CONFIRM': 'Confirm',
        'KANBAN.CARD.STATUS.BACK': 'Back',
      };

      return translations[key] || key;
    },
  }),
}));

const mountBadge = props =>
  mount(KanbanCardStatusBadge, {
    attachTo: document.body,
    props: {
      kanbanStageId: 1,
      wonStageId: 2,
      lostStageId: 3,
      reasons: [],
      lostReasonRequired: false,
      disabled: false,
      ...props,
    },
  });

const body = () => new DOMWrapper(document.body);

describe('KanbanCardStatusBadge', () => {
  it('renders nothing when won/lost stages are not configured', () => {
    const wrapper = mountBadge({ wonStageId: null, lostStageId: null });

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').exists()
    ).toBe(false);
  });

  it('shows the open label when the card is on a normal stage', () => {
    const wrapper = mountBadge({ kanbanStageId: 1 });

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').text()
    ).toContain('Open');
  });

  it('shows the won label when the card is on the won stage', () => {
    const wrapper = mountBadge({ kanbanStageId: 2 });

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').text()
    ).toContain('Won');
  });

  it('shows the lost label when the card is on the lost stage', () => {
    const wrapper = mountBadge({ kanbanStageId: 3 });

    expect(
      wrapper.find('[data-testid="kanban-card-status-badge"]').text()
    ).toContain('Lost');
  });

  it('picks a reason and confirms, emitting the won target stage and reason', async () => {
    const wrapper = mountBadge({
      reasons: [
        { id: 10, title: 'Great fit', reason_type: 'won' },
        { id: 11, title: 'Budget', reason_type: 'lost' },
      ],
    });

    await wrapper
      .find('[data-testid="kanban-card-status-badge"]')
      .trigger('click');
    await body()
      .find('[data-testid="kanban-card-status-option-won"]')
      .trigger('click');
    await body()
      .find('[data-testid="kanban-card-status-reason-select"] select')
      .setValue(10);
    await body()
      .find('[data-testid="kanban-card-status-confirm"]')
      .trigger('click');

    expect(wrapper.emitted('change')).toEqual([
      [{ targetStageId: 2, reasonId: 10 }],
    ]);
  });

  it('closes in one click when the board has no reason to pick', async () => {
    const wrapper = mountBadge({
      reasons: [{ id: 11, title: 'Budget', reason_type: 'lost' }],
    });

    await wrapper
      .find('[data-testid="kanban-card-status-badge"]')
      .trigger('click');
    await body()
      .find('[data-testid="kanban-card-status-option-won"]')
      .trigger('click');

    expect(
      body().find('[data-testid="kanban-card-status-confirm"]').exists()
    ).toBe(false);
    expect(wrapper.emitted('change')).toEqual([
      [{ targetStageId: 2, reasonId: null }],
    ]);
  });

  it('disables confirm when a lost reason is required but none is selected', async () => {
    const wrapper = mountBadge({
      lostReasonRequired: true,
      reasons: [{ id: 11, title: 'Budget', reason_type: 'lost' }],
    });

    await wrapper
      .find('[data-testid="kanban-card-status-badge"]')
      .trigger('click');
    await body()
      .find('[data-testid="kanban-card-status-option-lost"]')
      .trigger('click');

    const confirmButton = body().find(
      '[data-testid="kanban-card-status-confirm"]'
    );
    expect(confirmButton.attributes('disabled')).toBeDefined();

    await confirmButton.trigger('click');
    expect(wrapper.emitted('change')).toBeUndefined();
  });
});
