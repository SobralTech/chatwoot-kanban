import { mount } from '@vue/test-utils';

import KanbanAgendaDayCell from '../agenda/KanbanAgendaDayCell.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/components-next/popover/Popover.vue', () => ({
  default: {
    data: () => ({ isOpen: false }),
    methods: {
      hide() {
        this.isOpen = false;
      },
    },
    template: `
      <div>
        <span @click="isOpen = true"><slot /></span>
        <slot v-if="isOpen" name="content" :hide="hide" />
      </div>
    `,
  },
}));

describe('KanbanAgendaDayCell', () => {
  it('offers both creation actions for its date', async () => {
    const date = new Date(2026, 8, 2);
    const wrapper = mount(KanbanAgendaDayCell, { props: { date } });

    await wrapper.find('[data-testid="kanban-agenda-add"]').trigger('click');

    expect(
      wrapper.find('[data-testid="kanban-agenda-create-new"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="kanban-agenda-schedule-existing"]').exists()
    ).toBe(true);

    await wrapper
      .find('[data-testid="kanban-agenda-schedule-existing"]')
      .trigger('click');
    expect(wrapper.emitted('scheduleExisting')[0][0]).toBe(date);
  });
});
