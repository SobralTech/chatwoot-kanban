import {
  ACTION_NAMES,
  actionError,
  castActionParams,
  defaultActionParams,
} from '../automations/ruleActionSchema';

describe('rule action schema', () => {
  it('offers every action the engine implements', () => {
    expect(ACTION_NAMES).toEqual([
      'move_to_stage',
      'assign_agents',
      'set_priority',
      'add_label',
      'remove_label',
      'send_message',
      'create_note',
      'send_private_note',
      'set_due_at',
      'mark_as_lost',
    ]);
  });

  it('hands back a fresh defaults object each time', () => {
    const first = defaultActionParams('assign_agents');
    first.agent_ids.push(1);

    expect(defaultActionParams('assign_agents').agent_ids).toEqual([]);
  });

  it('requires agents unless the mode picks them', () => {
    expect(
      actionError({
        action_name: 'assign_agents',
        action_params: { mode: 'set', agent_ids: [] },
      })
    ).toBe('ACTION_AGENTS_REQUIRED');
    expect(
      actionError({
        action_name: 'assign_agents',
        action_params: { mode: 'round_robin', agent_ids: [] },
      })
    ).toBeNull();
  });

  it('rejects a due date of less than a day', () => {
    expect(
      actionError({ action_name: 'set_due_at', action_params: { days: 0 } })
    ).toBe('ACTION_DAYS_REQUIRED');
    expect(
      actionError({ action_name: 'set_due_at', action_params: { days: 3 } })
    ).toBeNull();
  });

  it('casts ids coming back from the selects as strings', () => {
    expect(
      castActionParams({
        action_name: 'assign_agents',
        action_params: { agent_ids: ['4', '7'], mode: 'set' },
      })
    ).toEqual({ agent_ids: [4, 7], mode: 'set' });

    expect(
      castActionParams({
        action_name: 'move_to_stage',
        action_params: { stage_id: '12' },
      })
    ).toEqual({ stage_id: 12 });
  });

  it('leaves an empty id alone rather than turning it into a zero', () => {
    expect(
      castActionParams({
        action_name: 'mark_as_lost',
        action_params: { reason_id: '' },
      })
    ).toEqual({ reason_id: '' });
  });
});
