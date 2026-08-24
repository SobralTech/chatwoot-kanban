import { mount } from '@vue/test-utils';

import KanbanStageSelect from '../KanbanStageSelect.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key =>
      (
        ({
          'CONVERSATION_SIDEBAR.KANBAN.STAGE_SELECT': 'Change stage',
          'KANBAN.CARD.UNKNOWN_STAGE': 'Unknown stage',
        })[key] || key
      ).toString(),
  }),
}));

const popoverStub = {
  name: 'Popover',
  template: `
    <div>
      <slot />
      <slot name="content" :hide="hide" />
    </div>
  `,
  setup() {
    const hide = vi.fn();
    return { hide };
  },
};

const stages = [
  { id: 20, name: 'Qualified', color: '#25c16b' },
  { id: 25, name: 'Proposal', color: '#1f93ff' },
];

const mountSelect = (props = {}) =>
  mount(KanbanStageSelect, {
    props: {
      modelValue: 20,
      stages,
      ...props,
    },
    global: {
      stubs: { Popover: popoverStub },
    },
  });

describe('KanbanStageSelect', () => {
  it('paints the current stage dot with the real stage color', () => {
    const wrapper = mountSelect();

    expect(
      wrapper
        .find('[data-testid="kanban-stage-select-trigger"] span')
        .attributes('style')
    ).toContain('rgb(37, 193, 107)');
  });

  it('lists every stage with its own color and marks the current one', async () => {
    const wrapper = mountSelect();

    await wrapper
      .get('[data-testid="kanban-stage-select-trigger"]')
      .trigger('click');

    const options = wrapper.findAll(
      '[data-testid="kanban-stage-select-option"]'
    );
    expect(options.map(option => option.text())).toEqual([
      'Qualified',
      'Proposal',
    ]);
    expect(options[0].find('span').attributes('style')).toContain(
      'rgb(37, 193, 107)'
    );
    expect(options[1].find('span').attributes('style')).toContain(
      'rgb(31, 147, 255)'
    );
    expect(options[0].classes()).toContain('bg-n-alpha-1');
    expect(options[0].find('.i-lucide-check').exists()).toBe(true);
    expect(options[1].find('.i-lucide-check').exists()).toBe(false);
  });

  it('emits the numeric id of the chosen stage', async () => {
    const wrapper = mountSelect();

    await wrapper
      .get('[data-testid="kanban-stage-select-trigger"]')
      .trigger('click');
    await wrapper
      .findAll('[data-testid="kanban-stage-select-option"]')[1]
      .trigger('click');

    expect(wrapper.emitted('update:modelValue')?.[0]).toEqual([25]);
  });

  it('falls back to a plain label when the list is empty', () => {
    const wrapper = mountSelect({
      stages: [],
      currentStage: { id: 40, name: 'Lost', color: '#ff0000' },
    });

    expect(
      wrapper.find('[data-testid="kanban-stage-select-trigger"]').exists()
    ).toBe(false);
    expect(wrapper.text()).toContain('Lost');
  });

  it('falls back to a plain label when the card sits outside the list', () => {
    const wrapper = mountSelect({
      modelValue: 30,
      currentStage: { id: 30, name: 'Won', color: '#00ff00' },
    });

    expect(
      wrapper.find('[data-testid="kanban-stage-select-trigger"]').exists()
    ).toBe(false);
    expect(wrapper.text()).toContain('Won');
  });
});
