import { shallowMount } from '@vue/test-utils';
import KanbanStageMenu from '../KanbanStageMenu.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

const buildStage = overrides => ({
  id: 10,
  name: 'Open',
  kanbanBoardId: 1,
  cardsCount: 0,
  ...overrides,
});

const findButton = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text().includes(label));

const mountMenu = ({
  stage = buildStage(),
  stages = [stage, buildStage({ id: 11, name: 'Qualified' })],
  boards = [
    { id: 1, name: 'Sales', stagesSummary: stages },
    { id: 2, name: 'Renewals', stagesSummary: [] },
  ],
  wonStageId = null,
  lostStageId = null,
  isAdmin = true,
} = {}) =>
  shallowMount(KanbanStageMenu, {
    props: {
      stage,
      stages,
      boards,
      wonStageId,
      lostStageId,
      isAdmin,
    },
    global: {
      stubs: {
        Popover: {
          name: 'Popover',
          props: ['align'],
          template:
            '<div><slot /><slot name="content" :hide="() => {}" /></div>',
        },
      },
    },
  });

describe('KanbanStageMenu', () => {
  it('opens its popover beside the list instead of over it', () => {
    const wrapper = mountMenu();

    expect(wrapper.findComponent({ name: 'Popover' }).props('align')).toBe(
      'start'
    );
  });

  it('only offers valid boards for a non-empty list', async () => {
    const stage = buildStage({ cardsCount: 2 });
    const wrapper = mountMenu({ stage });

    await findButton(wrapper, 'KANBAN.STAGE_MENU.MOVE.LABEL').trigger('click');

    const boardOptions = wrapper.findAll('select').at(0).findAll('option');

    expect(boardOptions).toHaveLength(1);
    expect(boardOptions[0].text()).toBe('Sales');
    expect(wrapper.text()).toContain('KANBAN.STAGE_MENU.MOVE.NONEMPTY_HINT');
  });

  it('excludes the source and terminal lists from bulk move destinations', async () => {
    const stage = buildStage();
    const qualified = buildStage({ id: 11, name: 'Qualified' });
    const won = buildStage({ id: 20, name: 'Won' });
    const lost = buildStage({ id: 30, name: 'Lost' });
    const wrapper = mountMenu({
      stage,
      stages: [stage, qualified, won, lost],
      wonStageId: won.id,
      lostStageId: lost.id,
    });

    await findButton(wrapper, 'KANBAN.STAGE_MENU.MOVE_CARDS.LABEL').trigger(
      'click'
    );

    expect(wrapper.text()).toContain('Qualified');
    expect(wrapper.text()).not.toContain('Won');
    expect(wrapper.text()).not.toContain('Lost');
    expect(wrapper.text()).not.toContain(
      'KANBAN.STAGE_MENU.MOVE_CARDS.CURRENT'
    );
  });

  it('hides unsupported actions for terminal lists', () => {
    const stage = buildStage({ id: 20, name: 'Won' });
    const wrapper = mountMenu({
      stage,
      stages: [stage, buildStage({ id: 11, name: 'Qualified' })],
      wonStageId: stage.id,
    });

    expect(findButton(wrapper, 'KANBAN.STAGE_MENU.ADD_CARD')).toBeUndefined();
    expect(findButton(wrapper, 'KANBAN.STAGE_MENU.MOVE.LABEL')).toBeUndefined();
    expect(
      findButton(wrapper, 'KANBAN.STAGE_MENU.MOVE_CARDS.LABEL')
    ).toBeUndefined();
    expect(findButton(wrapper, 'KANBAN.STAGE_MENU.EDIT')).toBeDefined();
  });

  it('hides list deletion when it is the only list', () => {
    const stage = buildStage();
    const wrapper = mountMenu({ stages: [stage] });

    expect(
      findButton(wrapper, 'KANBAN.STAGE_MENU.DELETE_STAGE')
    ).toBeUndefined();
    expect(findButton(wrapper, 'KANBAN.STAGE_MENU.DELETE_CARDS')).toBeDefined();
  });
});
