const HOUR_IN_MS = 3_600_000;

// A card is warned about once it has spent this share of the stage time limit,
// which gives an agent a window to act before the card actually goes stale.
export const SLA_WARNING_RATIO = 0.7;

export const SLA_FRESH = 'fresh';
export const SLA_WARNING = 'warning';
export const SLA_STALE = 'stale';

export const stageSlaStatus = ({
  stageEnteredAt,
  slaHours,
  now = Date.now(),
}) => {
  if (!slaHours || !stageEnteredAt) return SLA_FRESH;

  const ageHours = (now - new Date(stageEnteredAt).getTime()) / HOUR_IN_MS;
  if (ageHours >= slaHours) return SLA_STALE;
  if (ageHours >= slaHours * SLA_WARNING_RATIO) return SLA_WARNING;
  return SLA_FRESH;
};
