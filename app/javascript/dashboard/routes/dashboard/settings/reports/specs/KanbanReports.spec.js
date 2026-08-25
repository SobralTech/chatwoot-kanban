import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanReports from '../KanbanReports.vue';

const mocks = vi.hoisted(() => ({
  route: { query: {} },
  replace: vi.fn(),
  getDashboard: vi.fn(),
  getCsv: vi.fn(),
  alert: vi.fn(),
  download: vi.fn(),
}));

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useRoute: () => mocks.route,
    useRouter: () => ({ replace: mocks.replace }),
  };
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => (values ? `${key}:${JSON.stringify(values)}` : key),
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.alert,
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => ({
    value: {
      'agents/getAgents': [{ id: 2, name: 'Ana' }],
      'inboxes/getAllInboxes': [{ id: 3, name: 'Sales' }],
      'labels/getLabels': [{ id: 4, title: 'vip' }],
    }[key],
  }),
}));

vi.mock('dashboard/api/kanbanReports', () => ({
  default: {
    getDashboard: mocks.getDashboard,
    getCsv: mocks.getCsv,
  },
}));

vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: mocks.download,
}));

const reportData = {
  summary: {
    open: { count: 3, value: '300.00' },
    won: { count: 2, value: '200.00' },
    lost: { count: 1, value: '100.00' },
    average_ticket: '100.00',
    conversion_rate: 40,
  },
  conversion: [
    { stage_id: 1, stage_name: 'Qualified', count: 5, conversion_rate: 100 },
    { stage_id: 2, stage_name: 'Won', count: 2, conversion_rate: 40 },
  ],
  stage_times: [],
  won_lost: { series: [{ period: '2026-08-25', won: 2, lost: 1 }] },
  loss_reasons: [],
  agents: [],
  products: [],
};

const buildStore = () =>
  createStore({
    actions: {
      'agents/get': vi.fn(),
      'inboxes/get': vi.fn(),
      'labels/get': vi.fn(),
    },
  });

const mountReport = () =>
  shallowMount(KanbanReports, {
    global: {
      plugins: [buildStore()],
      mocks: {
        $t: (key, values) =>
          values ? `${key}:${JSON.stringify(values)}` : key,
      },
      stubs: {
        ReportHeader: true,
        ReportMetricCard: {
          props: ['label', 'value'],
          template: '<div data-test="metric">{{ label }} {{ value }}</div>',
        },
        WootDatePicker: true,
        FilterSelect: {
          name: 'FilterSelect',
          props: ['modelValue'],
          template: '<div />',
        },
        MultiSelect: true,
        BarChart: true,
        EmptyState: true,
        KanbanReportTable: {
          name: 'KanbanReportTable',
          props: ['title'],
          emits: ['download'],
          template:
            '<section><h2>{{ title }}</h2><button class="download" @click="$emit(\'download\')">download</button></section>',
        },
      },
    },
  });

describe('KanbanReports.vue', () => {
  beforeEach(() => {
    mocks.route.query = {};
    mocks.replace.mockReset();
    mocks.getDashboard.mockReset();
    mocks.getDashboard.mockImplementation(params =>
      Promise.resolve(
        params?.boardId
          ? { data: { ...reportData, boards: [{ id: 1, name: 'Sales' }] } }
          : { data: { boards: [{ id: 1, name: 'Sales' }] } }
      )
    );
    mocks.getCsv.mockReset();
    mocks.getCsv.mockResolvedValue({ data: 'csv data' });
    mocks.alert.mockReset();
    mocks.download.mockReset();
  });

  it('loads and renders the summary and funnel data', async () => {
    const wrapper = mountReport();
    await flushPromises();

    expect(mocks.getDashboard).toHaveBeenCalledTimes(2);
    expect(wrapper.text()).toContain('REPORT.KANBAN.SUMMARY.OPEN 3');
    expect(wrapper.text()).toContain('REPORT.KANBAN.SUMMARY.CONVERSION 40%');
    expect(wrapper.text()).toContain('Qualified');
    expect(wrapper.text()).toContain('Won');
  });

  it('refetches when the board filter changes', async () => {
    const wrapper = mountReport();
    await flushPromises();

    await wrapper
      .findAllComponents({ name: 'FilterSelect' })[0]
      .vm.$emit('update:modelValue', 2);
    await flushPromises();

    expect(mocks.getDashboard).toHaveBeenLastCalledWith(
      expect.objectContaining({ boardId: 2 })
    );
    expect(mocks.replace).toHaveBeenLastCalledWith({
      query: expect.objectContaining({ kanban_board_id: 2 }),
    });
  });

  it('downloads the selected table as CSV', async () => {
    const wrapper = mountReport();
    await flushPromises();

    await wrapper
      .findAllComponents({ name: 'KanbanReportTable' })[0]
      .vm.$emit('download');
    await flushPromises();

    expect(mocks.getCsv).toHaveBeenCalledWith(
      'conversion',
      expect.objectContaining({ boardId: 1 })
    );
    expect(mocks.download).toHaveBeenCalledWith(
      'kanban-conversion.csv',
      'csv data'
    );
  });
});
