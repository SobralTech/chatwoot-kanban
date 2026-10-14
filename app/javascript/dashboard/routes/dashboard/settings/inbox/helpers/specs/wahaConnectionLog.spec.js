import { groupConnectionLog } from '../wahaConnectionLog';

describe('groupConnectionLog', () => {
  it('returns no days for an empty history', () => {
    expect(groupConnectionLog([])).toEqual([]);
  });

  it('groups by day, newest first, collapsing consecutive repeated statuses', () => {
    const history = [
      { status: 'STARTING', timestamp: '2026-10-12T11:32:00' },
      { status: 'SCAN_QR_CODE', timestamp: '2026-10-12T11:32:30' },
      { status: 'SCAN_QR_CODE', timestamp: '2026-10-12T11:33:00' },
      { status: 'SCAN_QR_CODE', timestamp: '2026-10-12T11:34:00' },
      { status: 'FAILED', timestamp: '2026-10-12T11:34:30' },
      { status: 'STARTING', timestamp: '2026-10-13T15:04:00' },
      { status: 'WORKING', timestamp: '2026-10-13T15:04:10' },
    ];

    const days = groupConnectionLog(history);

    expect(days.map(day => day.entries)).toEqual([
      [
        {
          status: 'WORKING',
          count: 1,
          firstAt: '2026-10-13T15:04:10',
          lastAt: '2026-10-13T15:04:10',
        },
        {
          status: 'STARTING',
          count: 1,
          firstAt: '2026-10-13T15:04:00',
          lastAt: '2026-10-13T15:04:00',
        },
      ],
      [
        {
          status: 'FAILED',
          count: 1,
          firstAt: '2026-10-12T11:34:30',
          lastAt: '2026-10-12T11:34:30',
        },
        {
          status: 'SCAN_QR_CODE',
          count: 3,
          firstAt: '2026-10-12T11:32:30',
          lastAt: '2026-10-12T11:34:00',
        },
        {
          status: 'STARTING',
          count: 1,
          firstAt: '2026-10-12T11:32:00',
          lastAt: '2026-10-12T11:32:00',
        },
      ],
    ]);
  });

  it('does not collapse the same status across different days', () => {
    const days = groupConnectionLog([
      { status: 'SCAN_QR_CODE', timestamp: '2026-10-11T23:59:00' },
      { status: 'SCAN_QR_CODE', timestamp: '2026-10-12T00:01:00' },
    ]);

    expect(days).toHaveLength(2);
    expect(days.every(day => day.entries[0].count === 1)).toBe(true);
  });
});
