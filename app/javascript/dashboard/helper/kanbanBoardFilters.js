// Attributes a card can only ever hold one of, so selecting two of them in the
// "match all" mode would describe a card that cannot exist. Labels, assignees,
// and due date windows (which are combined with OR) are left out.
export const SINGLE_VALUE_FILTER_KEYS = [
  'inboxIds',
  'cardStatuses',
  'priorities',
];

export const applyMatchModeConstraints = filters => {
  if (filters.matchMode !== 'all') return filters;

  return SINGLE_VALUE_FILTER_KEYS.reduce(
    (acc, key) => ({ ...acc, [key]: acc[key].slice(0, 1) }),
    { ...filters }
  );
};

// Terminal stages (won/lost) are sliced by a time window instead of showing
// every card ever closed. The window applies to those two columns only.
export const TERMINAL_PERIODS = ['7d', '30d', '90d', 'all'];
export const DEFAULT_TERMINAL_PERIOD = '30d';
export const ALL_TIME_TERMINAL_PERIOD = 'all';

export const normalizeTerminalPeriod = value =>
  TERMINAL_PERIODS.includes(value) ? value : DEFAULT_TERMINAL_PERIOD;
