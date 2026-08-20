export const stageSlaStatus = ({
  stageEnteredAt,
  slaHours,
  now = Date.now(),
}) => {
  if (!slaHours || !stageEnteredAt) return 'fresh';

  const ageHours = (now - new Date(stageEnteredAt).getTime()) / 3_600_000;
  if (ageHours >= slaHours) return 'stale';
  if (ageHours >= slaHours * 0.7) return 'warning';
  return 'fresh';
};
