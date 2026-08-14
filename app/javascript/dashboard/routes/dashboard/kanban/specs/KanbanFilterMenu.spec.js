import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import KanbanFilterMenu from '../KanbanFilterMenu.vue';

const hide = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref([]),
}));

const mountMenu = () =>
  shallowMount(KanbanFilterMenu, {
    props: {
      modelValue: {
        inboxIds: [],
        assigneeIds: [],
        cardStatuses: [],
        priorities: [],
        dueDates: [],
        labels: [],
        matchMode: 'any',
      },
    },
    global: {
      stubs: {
        Popover: {
          name: 'Popover',
          setup() {
            return { hide };
          },
          template: '<div><slot /><slot name="content" :hide="hide" /></div>',
        },
      },
    },
  });

describe('KanbanFilterMenu', () => {
  beforeEach(() => {
    hide.mockClear();
  });

  it('provides an explicit close control for the filter menu', async () => {
    const wrapper = mountMenu();
    const closeButton = wrapper.find(
      '[data-testid="kanban-filter-menu-close"]'
    );

    expect(closeButton.attributes('aria-label')).toBe('KANBAN.FILTERS.CLOSE');

    await closeButton.trigger('click');

    expect(hide).toHaveBeenCalledOnce();
  });
});
