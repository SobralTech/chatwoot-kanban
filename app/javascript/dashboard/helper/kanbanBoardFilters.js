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
