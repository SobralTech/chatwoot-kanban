import {
  messageStamp,
  messageTimestamp,
  dynamicTime,
  dateFormat,
  shortTimestamp,
  getDayDifferenceFromNow,
  hasOneDayPassed,
} from 'shared/helpers/timeHelper';

beforeEach(() => {
  process.env.TZ = 'UTC';
  vi.useFakeTimers('modern');
  const mockDate = new Date(Date.UTC(2023, 4, 5));
  vi.setSystemTime(mockDate);
});

afterEach(() => {
  vi.useRealTimers();
});

describe('#messageStamp', () => {
  it('returns correct value', () => {
    expect(messageStamp(1612971343)).toEqual('3:35 PM');
    expect(messageStamp(1612971343, 'LLL d, h:mm a')).toEqual(
      'Feb 10, 3:35 PM'
    );
  });
});

describe('#messageTimestamp', () => {
  it('should return the message date in the specified format if the message was sent in the current year', () => {
    expect(messageTimestamp(1680777464)).toEqual('Apr 6, 2023');
  });
  it('should return the message date and time in a different format if the message was sent in a different year', () => {
    expect(messageTimestamp(1612971343)).toEqual('Feb 10 2021, 3:35 PM');
  });
});

describe('#dynamicTime', () => {
  it('returns correct value', () => {
    Date.now = vi.fn(() => new Date(Date.UTC(2023, 1, 14)).valueOf());
    expect(dynamicTime(1612971343)).toEqual('há cerca de 2 anos');
  });
});

describe('#dateFormat', () => {
  it('returns correct value', () => {
    expect(dateFormat(1612971343)).toEqual('Feb 10, 2021');
    expect(dateFormat(1612971343, 'LLL d, yyyy')).toEqual('Feb 10, 2021');
  });
});

describe('#shortTimestamp', () => {
  // Test cases when withAgo is false or not provided
  it('returns correct value without ago', () => {
    expect(shortTimestamp('em menos de um minuto')).toEqual('agora');
    expect(shortTimestamp('há menos de um minuto')).toEqual('agora');
    expect(shortTimestamp('há meio minuto')).toEqual('agora');
    expect(shortTimestamp('há 1 minuto')).toEqual('1m');
    expect(shortTimestamp('há 12 minutos')).toEqual('12m');
    expect(shortTimestamp('há cerca de 1 hora')).toEqual('1h');
    expect(shortTimestamp('há 1 hora')).toEqual('1h');
    expect(shortTimestamp('há 2 horas')).toEqual('2h');
    expect(shortTimestamp('há 1 dia')).toEqual('1d');
    expect(shortTimestamp('há 3 dias')).toEqual('3d');
    expect(shortTimestamp('há cerca de 1 mês')).toEqual('1mo');
    expect(shortTimestamp('há 1 mês')).toEqual('1mo');
    expect(shortTimestamp('há 2 meses')).toEqual('2mo');
    expect(shortTimestamp('há cerca de 1 ano')).toEqual('1y');
    expect(shortTimestamp('há 1 ano')).toEqual('1y');
    expect(shortTimestamp('há 4 anos')).toEqual('4y');
  });

  // Test cases when withAgo is true
  it('returns correct value with ago', () => {
    expect(shortTimestamp('há menos de um minuto', true)).toEqual('agora');
    expect(shortTimestamp('há 1 minuto', true)).toEqual('1m atrás');
    expect(shortTimestamp('há 12 minutos', true)).toEqual('12m atrás');
    expect(shortTimestamp('há cerca de 1 hora', true)).toEqual('1h atrás');
    expect(shortTimestamp('há 1 hora', true)).toEqual('1h atrás');
    expect(shortTimestamp('há 2 horas', true)).toEqual('2h atrás');
    expect(shortTimestamp('há 1 dia', true)).toEqual('1d atrás');
    expect(shortTimestamp('há 3 dias', true)).toEqual('3d atrás');
    expect(shortTimestamp('há cerca de 1 mês', true)).toEqual('1mo atrás');
    expect(shortTimestamp('há 1 mês', true)).toEqual('1mo atrás');
    expect(shortTimestamp('há 2 meses', true)).toEqual('2mo atrás');
    expect(shortTimestamp('há cerca de 1 ano', true)).toEqual('1y atrás');
    expect(shortTimestamp('há 1 ano', true)).toEqual('1y atrás');
    expect(shortTimestamp('há 4 anos', true)).toEqual('4y atrás');
  });
});

describe('#getDayDifferenceFromNow', () => {
  it('returns 0 for timestamps from today', () => {
    // Mock current date: May 5, 2023
    const now = new Date(Date.UTC(2023, 4, 5, 12, 0, 0)); // 12:00 PM
    const todayTimestamp = Math.floor(now.getTime() / 1000); // Same day

    expect(getDayDifferenceFromNow(now, todayTimestamp)).toEqual(0);
  });

  it('returns 2 for timestamps from 2 days ago', () => {
    const now = new Date(Date.UTC(2023, 4, 5, 12, 0, 0)); // May 5, 2023
    const twoDaysAgoTimestamp = Math.floor(
      new Date(Date.UTC(2023, 4, 3, 10, 0, 0)).getTime() / 1000
    ); // May 3, 2023

    expect(getDayDifferenceFromNow(now, twoDaysAgoTimestamp)).toEqual(2);
  });

  it('returns 7 for timestamps from a week ago', () => {
    const now = new Date(Date.UTC(2023, 4, 5, 12, 0, 0)); // May 5, 2023
    const weekAgoTimestamp = Math.floor(
      new Date(Date.UTC(2023, 3, 28, 8, 0, 0)).getTime() / 1000
    ); // April 28, 2023

    expect(getDayDifferenceFromNow(now, weekAgoTimestamp)).toEqual(7);
  });

  it('returns 30 for timestamps from a month ago', () => {
    const now = new Date(Date.UTC(2023, 4, 5, 12, 0, 0)); // May 5, 2023
    const monthAgoTimestamp = Math.floor(
      new Date(Date.UTC(2023, 3, 5, 12, 0, 0)).getTime() / 1000
    ); // April 5, 2023

    expect(getDayDifferenceFromNow(now, monthAgoTimestamp)).toEqual(30);
  });

  it('handles edge case with different times on same day', () => {
    const now = new Date(Date.UTC(2023, 4, 5, 23, 59, 59)); // May 5, 2023 11:59:59 PM
    const morningTimestamp = Math.floor(
      new Date(Date.UTC(2023, 4, 5, 0, 0, 1)).getTime() / 1000
    ); // May 5, 2023 12:00:01 AM

    expect(getDayDifferenceFromNow(now, morningTimestamp)).toEqual(0);
  });

  it('handles cross-month boundaries correctly', () => {
    const now = new Date(Date.UTC(2023, 4, 1, 12, 0, 0)); // May 1, 2023
    const lastMonthTimestamp = Math.floor(
      new Date(Date.UTC(2023, 3, 30, 12, 0, 0)).getTime() / 1000
    ); // April 30, 2023

    expect(getDayDifferenceFromNow(now, lastMonthTimestamp)).toEqual(1);
  });

  it('handles cross-year boundaries correctly', () => {
    const now = new Date(Date.UTC(2023, 0, 2, 12, 0, 0)); // January 2, 2023
    const lastYearTimestamp = Math.floor(
      new Date(Date.UTC(2022, 11, 31, 12, 0, 0)).getTime() / 1000
    ); // December 31, 2022

    expect(getDayDifferenceFromNow(now, lastYearTimestamp)).toEqual(2);
  });
});

describe('#hasOneDayPassed', () => {
  beforeEach(() => {
    // Mock current date: May 5, 2023, 12:00 PM UTC (1683288000)
    const mockDate = new Date(1683288000 * 1000);
    vi.setSystemTime(mockDate);
  });

  it('returns false for timestamps from today', () => {
    // Same day, different time - May 5, 2023 8:00 AM UTC
    const todayTimestamp = 1683273600;

    expect(hasOneDayPassed(todayTimestamp)).toBe(false);
  });

  it('returns false for timestamps from yesterday (less than 24 hours)', () => {
    // Yesterday but less than 24 hours ago - May 4, 2023 6:00 PM UTC (18 hours ago)
    const yesterdayTimestamp = 1683230400;

    expect(hasOneDayPassed(yesterdayTimestamp)).toBe(false);
  });

  it('returns true for timestamps from exactly 1 day ago', () => {
    // Exactly 24 hours ago - May 4, 2023 12:00 PM UTC
    const oneDayAgoTimestamp = 1683201600;

    expect(hasOneDayPassed(oneDayAgoTimestamp)).toBe(true);
  });

  it('returns true for timestamps from more than 1 day ago', () => {
    // 2 days ago - May 3, 2023 10:00 AM UTC
    const twoDaysAgoTimestamp = 1683108000;

    expect(hasOneDayPassed(twoDaysAgoTimestamp)).toBe(true);
  });

  it('returns true for timestamps from a week ago', () => {
    // 7 days ago - April 28, 2023 8:00 AM UTC
    const weekAgoTimestamp = 1682668800;

    expect(hasOneDayPassed(weekAgoTimestamp)).toBe(true);
  });

  it('returns true for null timestamp (defensive check)', () => {
    expect(hasOneDayPassed(null)).toBe(true);
  });

  it('returns true for undefined timestamp (defensive check)', () => {
    expect(hasOneDayPassed(undefined)).toBe(true);
  });

  it('returns true for zero timestamp (defensive check)', () => {
    expect(hasOneDayPassed(0)).toBe(true);
  });

  it('returns true for empty string timestamp (defensive check)', () => {
    expect(hasOneDayPassed('')).toBe(true);
  });

  it('handles cross-month boundaries correctly', () => {
    // Set current time to May 1, 2023 12:00 PM UTC (1682942400)
    const mayFirst = new Date(1682942400 * 1000);
    vi.setSystemTime(mayFirst);

    // April 29, 2023 12:00 PM UTC (1682769600) - 2 days ago, crossing month boundary
    const crossMonthTimestamp = 1682769600;

    expect(hasOneDayPassed(crossMonthTimestamp)).toBe(true);
  });

  it('handles cross-year boundaries correctly', () => {
    // Set current time to January 2, 2023 12:00 PM UTC (1672660800)
    const newYear = new Date(1672660800 * 1000);
    vi.setSystemTime(newYear);

    // December 30, 2022 12:00 PM UTC (1672401600) - 3 days ago, crossing year boundary
    const crossYearTimestamp = 1672401600;

    expect(hasOneDayPassed(crossYearTimestamp)).toBe(true);
  });
});
