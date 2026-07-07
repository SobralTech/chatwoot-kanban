import {
  format,
  isSameYear,
  isToday,
  isYesterday,
  fromUnixTime,
  formatDistanceToNow,
  differenceInDays,
  differenceInCalendarDays,
} from 'date-fns';
import { ptBR } from 'date-fns/locale';

/**
 * Formats a Unix timestamp into a human-readable time format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='h:mm a'] - Desired format of the time.
 * @returns {string} Formatted time string.
 */
export const messageStamp = (time, dateFormat = 'h:mm a') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, dateFormat);
};

/**
 * Provides a formatted timestamp, adjusting the format based on the current year.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const messageTimestamp = (time, dateFormat = 'MMM d, yyyy') => {
  const messageTime = fromUnixTime(time);
  const now = new Date();
  const messageDate = format(messageTime, dateFormat);
  if (!isSameYear(messageTime, now)) {
    return format(messageTime, 'LLL d y, HH:mm');
  }
  return messageDate;
};

export const humanTimestamp = time => {
  const messageTime = fromUnixTime(time);
  const timeStr = format(messageTime, 'HH:mm');
  if (isToday(messageTime)) return `Hoje, ${timeStr}`;
  if (isYesterday(messageTime)) return `Ontem, ${timeStr}`;
  const now = new Date();
  if (isSameYear(messageTime, now)) {
    return format(messageTime, `d 'de' MMMM, HH:mm`, { locale: ptBR });
  }
  return format(messageTime, `d 'de' MMMM 'de' yyyy, HH:mm`, { locale: ptBR });
};

/**
 * Formats a Unix timestamp as: time if today, "Ontem" if yesterday,
 * weekday name within the last week, or a full date otherwise.
 * @param {number} time - Unix timestamp.
 * @returns {string} Formatted timestamp string.
 */
export const relativeDayTimestamp = time => {
  const date = fromUnixTime(time);
  if (isToday(date)) return format(date, 'HH:mm');
  if (isYesterday(date)) return 'Ontem';
  const daysAgo = differenceInCalendarDays(new Date(), date);
  if (daysAgo <= 6) return format(date, 'EEEE', { locale: ptBR });
  return format(date, 'dd/MM/yyyy');
};

/**
 * Converts a Unix timestamp to a relative time string (e.g., 3 hours ago).
 * @param {number} time - Unix timestamp.
 * @returns {string} Relative time string.
 */
export const dynamicTime = time => {
  const unixTime = fromUnixTime(time);
  return formatDistanceToNow(unixTime, { addSuffix: true, locale: ptBR });
};

/**
 * Formats a Unix timestamp into a specified date format.
 * @param {number} time - Unix timestamp.
 * @param {string} [dateFormat='MMM d, yyyy'] - Desired date format.
 * @returns {string} Formatted date string.
 */
export const dateFormat = (time, df = 'MMM d, yyyy') => {
  const unixTime = fromUnixTime(time);
  return format(unixTime, df);
};

/**
 * Converts a detailed time description into a shorter format, optionally appending 'ago'.
 * @param {string} time - Detailed time description (e.g., 'a minute ago').
 * @param {boolean} [withAgo=false] - Whether to append 'ago' to the result.
 * @returns {string} Shortened time description.
 */
export const shortTimestamp = (time, withAgo = false) => {
  // This function takes a pt-BR relative time string (from dynamicTime) and
  // converts it to a short time string with the following format:
  // 1m, 1h, 1d, 1mo, 1y. The optional withAgo parameter appends "atrás".
  const suffix = withAgo ? ' atrás' : '';
  const timeMappings = {
    'há menos de um minuto': 'agora',
    'em menos de um minuto': 'agora',
    'há meio minuto': 'agora',
    'há 1 minuto': `1m${suffix}`,
    'há cerca de 1 hora': `1h${suffix}`,
    'há 1 hora': `1h${suffix}`,
    'há 1 dia': `1d${suffix}`,
    'há cerca de 1 mês': `1mo${suffix}`,
    'há 1 mês': `1mo${suffix}`,
    'há cerca de 1 ano': `1y${suffix}`,
    'há 1 ano': `1y${suffix}`,
  };
  // Check if the time string is one of the specific cases
  if (timeMappings[time]) {
    return timeMappings[time];
  }
  const convertToShortTime = time
    .replace(/^há |^em /, '')
    .replace(/cerca de |mais de |quase /g, '')
    .replace(' minutos', `m${suffix}`)
    .replace(' minuto', `m${suffix}`)
    .replace(' horas', `h${suffix}`)
    .replace(' hora', `h${suffix}`)
    .replace(' dias', `d${suffix}`)
    .replace(' dia', `d${suffix}`)
    .replace(' meses', `mo${suffix}`)
    .replace(' mês', `mo${suffix}`)
    .replace(' anos', `y${suffix}`)
    .replace(' ano', `y${suffix}`);
  return convertToShortTime;
};

/**
 * Formats a duration in seconds into mm:ss or hh:mm:ss.
 * @param {number|string} durationInSeconds - Duration in seconds.
 * @returns {string} Formatted duration string. Empty string for invalid input.
 */
export const formatDuration = durationInSeconds => {
  if (durationInSeconds === null || durationInSeconds === undefined) return '';

  const totalSeconds = Number(durationInSeconds);
  if (Number.isNaN(totalSeconds) || totalSeconds < 0) return '';

  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  const mm = minutes.toString().padStart(2, '0');
  const ss = seconds.toString().padStart(2, '0');
  if (hours > 0) {
    return `${hours.toString().padStart(2, '0')}:${mm}:${ss}`;
  }
  return `${mm}:${ss}`;
};

/**
 * Calculates the difference in days between now and a given timestamp.
 * @param {Date} now - Current date/time.
 * @param {number} timestampInSeconds - Unix timestamp in seconds.
 * @returns {number} Number of days difference.
 */
export const getDayDifferenceFromNow = (now, timestampInSeconds) => {
  const date = new Date(timestampInSeconds * 1000);
  return differenceInDays(now, date);
};

/**
 * Checks if more than 24 hours have passed since a given timestamp.
 * Useful for determining if retry/refresh actions should be disabled.
 * @param {number} timestamp - Unix timestamp.
 * @returns {boolean} True if more than 24 hours have passed.
 */
export const hasOneDayPassed = timestamp => {
  if (!timestamp) return true; // Defensive check
  return getDayDifferenceFromNow(new Date(), timestamp) >= 1;
};
