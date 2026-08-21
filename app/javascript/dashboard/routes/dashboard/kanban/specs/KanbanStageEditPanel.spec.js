import { mount } from '@vue/test-utils';

import KanbanStageEditPanel from '../KanbanStageEditPanel.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountPanel = (props = {}) =>
  mount(KanbanStageEditPanel, {
    props: { showColorPicker: true, showSlaHours: true, ...props },
    global: { stubs: { Button: true, ColorPicker: true } },
  });

describe('KanbanStageEditPanel', () => {
  it('hides the SLA field unless the stage supports a time limit', () => {
    const wrapper = mountPanel({ showSlaHours: false });

    expect(
      wrapper
        .find('[data-testid="kanban-board-form-edit-stage-sla-hours"]')
        .exists()
    ).toBe(false);
  });

  it('reports the SLA hours the user typed', async () => {
    const wrapper = mountPanel();

    await wrapper
      .find('[data-testid="kanban-board-form-edit-stage-sla-hours"]')
      .setValue('48');

    expect(wrapper.emitted()['update:slaHours'].at(-1)).toEqual([48]);
  });

  it('names its fields after the form it is rendering', () => {
    const wrapper = mountPanel({
      testidPrefix: 'kanban-board-form-new-stage',
      saveTestid: 'kanban-board-form-create-stage',
    });

    expect(
      wrapper.find('[data-testid="kanban-board-form-new-stage-name"]').exists()
    ).toBe(true);
    expect(
      wrapper
        .find('[data-testid="kanban-board-form-new-stage-sla-hours"]')
        .exists()
    ).toBe(true);
  });
});
