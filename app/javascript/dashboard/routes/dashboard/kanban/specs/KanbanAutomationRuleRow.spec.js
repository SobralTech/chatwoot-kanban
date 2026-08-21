import { mount } from '@vue/test-utils';
import KanbanAutomationRuleRow from '../automations/KanbanAutomationRuleRow.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => {
      const translations = {
        'KANBAN.AUTOMATIONS.FORM.EVENTS.STAGE_CHANGED':
          'When the stage changes',
        'KANBAN.AUTOMATIONS.FORM.CONDITIONS.STAGE': 'Stage',
        'FILTER.OPERATOR_LABELS.equal_to': 'is',
        'KANBAN.AUTOMATIONS.STATE.SIMULATION': 'Simulation',
        'KANBAN.AUTOMATIONS.STATE.ACTIVE': 'Active',
        'KANBAN.AUTOMATIONS.RUNS_7D': `${values?.count} runs`,
        'KANBAN.AUTOMATIONS.ROW.SUMMARY': `${values?.event} · ${values?.condition} · ${values?.count} actions`,
      };

      return translations[key] || key;
    },
  }),
}));

const rule = overrides => ({
  id: 7,
  name: 'Nudge stalled deals',
  event_name: 'stage_changed',
  conditions: [
    { attribute_key: 'stage_id', filter_operator: 'equal_to', values: [3] },
  ],
  actions: [{ action_name: 'send_message', action_params: { content: 'Hi' } }],
  active: true,
  dry_run: false,
  executions_count: 4,
  ...overrides,
});

const mountRow = overrides =>
  mount(KanbanAutomationRuleRow, {
    props: {
      rule: rule(overrides),
      stages: [{ id: 3, name: 'Negotiation' }],
      automationsEnabled: true,
    },
    global: { stubs: { Button: true, DropdownContainer: true } },
  });

describe('KanbanAutomationRuleRow', () => {
  it('summarises the rule from the payload the API sends', () => {
    // The API speaks snake_case here, and the summary once read camelCase keys off it
    // and rendered "If undefined undefined 3" to the user.
    expect(mountRow().text()).toContain(
      'When the stage changes · Stage is Negotiation · 1 actions'
    );
  });

  it('reports the state a rule is really in', () => {
    expect(mountRow({ dry_run: true }).text()).toContain('Simulation');
    expect(mountRow().text()).toContain('Active');
    expect(mountRow().text()).toContain('4 runs');
  });
});
