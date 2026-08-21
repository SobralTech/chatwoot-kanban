import { mount } from '@vue/test-utils';

import KanbanStageEditPanel from '../KanbanStageEditPanel.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('KanbanStageEditPanel', () => {
  it('keeps the SLA field within the available stage edit width', () => {
    const wrapper = mount(KanbanStageEditPanel, {
      props: {
        showColorPicker: true,
        showSlaHours: true,
      },
      global: {
        stubs: {
          Button: true,
          ColorPicker: true,
        },
      },
    });

    const nameInput = wrapper.find(
      '[data-testid="kanban-board-form-edit-stage-name"]'
    );
    const slaLabel = nameInput.element.parentElement.querySelector('label');
    const slaInput = wrapper.find(
      '[data-testid="kanban-board-form-edit-stage-sla-hours"]'
    );

    expect(nameInput.classes()).toEqual(
      expect.arrayContaining(['w-0', 'min-w-0'])
    );
    expect([...slaLabel.classList]).toEqual(
      expect.arrayContaining(['max-w-full', 'min-w-0'])
    );
    expect(slaInput.classes()).toEqual(
      expect.arrayContaining(['w-full', 'min-w-0'])
    );
  });
});
