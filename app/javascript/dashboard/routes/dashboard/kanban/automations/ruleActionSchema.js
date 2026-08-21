// One row per action: what it defaults to, what it needs, how its params are typed on
// the way out, and which field the form renders. The options list, the defaults, the
// validation, the payload coercion and the template all read from here, so adding an
// action means adding a row.
export const ACTION_SCHEMA = [
  {
    name: 'move_to_stage',
    field: 'stage',
    defaults: () => ({ stage_id: '' }),
    required: params => (params.stage_id ? null : 'ACTION_STAGE_REQUIRED'),
    numeric: ['stage_id'],
  },
  {
    name: 'assign_agents',
    field: 'agents',
    defaults: () => ({ agent_ids: [], mode: 'set' }),
    required: params => {
      if (!params.mode) return 'ACTION_MODE_REQUIRED';
      if (params.mode === 'round_robin') return null;
      return params.agent_ids?.length ? null : 'ACTION_AGENTS_REQUIRED';
    },
    numericList: ['agent_ids'],
  },
  {
    name: 'set_priority',
    field: 'priority',
    defaults: () => ({ priority: '' }),
    required: params => (params.priority ? null : 'ACTION_PRIORITY_REQUIRED'),
  },
  {
    name: 'add_label',
    field: 'labels',
    defaults: () => ({ labels: [] }),
    required: params =>
      params.labels?.length ? null : 'ACTION_LABELS_REQUIRED',
  },
  {
    name: 'remove_label',
    field: 'labels',
    defaults: () => ({ labels: [] }),
    required: params =>
      params.labels?.length ? null : 'ACTION_LABELS_REQUIRED',
  },
  {
    name: 'send_message',
    field: 'message',
    defaults: () => ({ content: '' }),
    required: params =>
      params.content?.trim() ? null : 'ACTION_CONTENT_REQUIRED',
  },
  {
    name: 'create_note',
    field: 'message',
    defaults: () => ({ content: '' }),
    required: params =>
      params.content?.trim() ? null : 'ACTION_CONTENT_REQUIRED',
  },
  {
    name: 'send_private_note',
    field: 'message',
    defaults: () => ({ content: '' }),
    required: params =>
      params.content?.trim() ? null : 'ACTION_CONTENT_REQUIRED',
  },
  {
    name: 'set_due_at',
    field: 'dueAt',
    defaults: () => ({ days: 1, business_days: false }),
    required: params =>
      Number(params.days) >= 1 ? null : 'ACTION_DAYS_REQUIRED',
    numeric: ['days'],
  },
  {
    name: 'mark_as_lost',
    field: 'reason',
    defaults: () => ({ reason_id: '' }),
    required: params => (params.reason_id ? null : 'ACTION_REASON_REQUIRED'),
    numeric: ['reason_id'],
  },
];

export const ACTION_NAMES = ACTION_SCHEMA.map(action => action.name);

const byName = Object.fromEntries(
  ACTION_SCHEMA.map(action => [action.name, action])
);

export const actionSchema = name => byName[name] || null;

export const defaultActionParams = name =>
  byName[name] ? byName[name].defaults() : {};

export const actionError = action =>
  byName[action.action_name]?.required(action.action_params || {}) || null;

// The API wants ids as numbers; the selects hand back strings.
export const castActionParams = action => {
  const schema = byName[action.action_name];
  const params = { ...(action.action_params || {}) };
  if (!schema) return params;

  (schema.numeric || []).forEach(key => {
    if (params[key] !== undefined && params[key] !== '') {
      params[key] = Number(params[key]);
    }
  });
  (schema.numericList || []).forEach(key => {
    if (Array.isArray(params[key])) params[key] = params[key].map(Number);
  });
  return params;
};
