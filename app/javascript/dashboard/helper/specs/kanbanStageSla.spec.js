import { stageSlaStatus } from 'dashboard/helper/kanbanStageSla';

describe('stageSlaStatus', () => {
  const now = Date.parse('2026-08-20T12:00:00Z');
  const enteredAt = hoursAgo =>
    new Date(now - hoursAgo * 3_600_000).toISOString();

  it('returns fresh before the warning threshold', () => {
    expect(
      stageSlaStatus({ stageEnteredAt: enteredAt(10), slaHours: 24, now })
    ).toBe('fresh');
  });

  it('returns warning between 70% and 100% of the SLA', () => {
    expect(
      stageSlaStatus({ stageEnteredAt: enteredAt(20), slaHours: 24, now })
    ).toBe('warning');
  });

  it('returns stale at the SLA limit', () => {
    expect(
      stageSlaStatus({ stageEnteredAt: enteredAt(24), slaHours: 24, now })
    ).toBe('stale');
  });

  it.each([
    { stageEnteredAt: null, slaHours: 24 },
    { stageEnteredAt: enteredAt(48), slaHours: null },
  ])('returns fresh when the stage has no SLA data: %o', values => {
    expect(stageSlaStatus({ ...values, now })).toBe('fresh');
  });
});
