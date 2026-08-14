// Attributes a card can only ever hold one of, so selecting two of them in the
// "match all" mode would describe a card that cannot exist. Labels and assignees
// are left out: a card can carry several of each.
export const SINGLE_VALUE_FILTER_KEYS = [
  'inboxIds',
  'cardStatuses',
  'priorities',
  'dueDates',
];

export const applyMatchModeConstraints = filters => {
  if (filters.matchMode !== 'all') return filters;

  return SINGLE_VALUE_FILTER_KEYS.reduce(
    (acc, key) => ({ ...acc, [key]: acc[key].slice(0, 1) }),
    { ...filters }
  );
};
