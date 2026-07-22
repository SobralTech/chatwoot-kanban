import { parseISO, isValid as isValidDate } from 'date-fns';
import DOMPurify from 'dompurify';

/**
 * Extracts plain text from HTML content
 * @param {string} html - HTML content to convert
 * @returns {string} Plain text content
 */
export const extractPlainTextFromHtml = html => {
  if (!html) {
    return '';
  }
  if (typeof document === 'undefined') {
    return html.replace(/<[^>]*>/g, ' ');
  }
  const tempDiv = document.createElement('div');
  tempDiv.innerHTML = DOMPurify.sanitize(html);
  return tempDiv.textContent || tempDiv.innerText || '';
};

/**
 * Extracts sender name from email message
 * @param {Object} lastEmail - Last email message object
 * @param {Object} contact - Contact object
 * @returns {string} Sender name
 */
export const getEmailSenderName = (lastEmail, contact) => {
  const senderName = lastEmail?.sender?.name;
  if (senderName && senderName.trim()) {
    return senderName.trim();
  }

  const contactName = contact?.name;
  return contactName && contactName.trim() ? contactName.trim() : '';
};

/**
 * Extracts sender email from email message
 * @param {Object} lastEmail - Last email message object
 * @param {Object} contact - Contact object
 * @returns {string} Sender email address
 */
export const getEmailSenderEmail = (lastEmail, contact) => {
  const senderEmail = lastEmail?.sender?.email;
  if (senderEmail && senderEmail.trim()) {
    return senderEmail.trim();
  }

  const contentAttributes =
    lastEmail?.contentAttributes || lastEmail?.content_attributes || {};
  const emailMeta = contentAttributes.email || {};

  if (Array.isArray(emailMeta.from) && emailMeta.from.length > 0) {
    const fromAddress = emailMeta.from[0];
    if (fromAddress && fromAddress.trim()) {
      return fromAddress.trim();
    }
  }

  const contactEmail = contact?.email;
  return contactEmail && contactEmail.trim() ? contactEmail.trim() : '';
};

/**
 * Extracts date from email message
 * @param {Object} lastEmail - Last email message object
 * @returns {Date|null} Email date
 */
export const getEmailDate = lastEmail => {
  const contentAttributes =
    lastEmail?.contentAttributes || lastEmail?.content_attributes || {};
  const emailMeta = contentAttributes.email || {};

  if (emailMeta.date) {
    const parsedDate = parseISO(emailMeta.date);
    if (isValidDate(parsedDate)) {
      return parsedDate;
    }
  }

  const createdAt = lastEmail?.created_at;
  if (createdAt) {
    const timestamp = Number(createdAt);
    if (!Number.isNaN(timestamp)) {
      const milliseconds = timestamp > 1e12 ? timestamp : timestamp * 1000;
      const derivedDate = new Date(milliseconds);
      if (!Number.isNaN(derivedDate.getTime())) {
        return derivedDate;
      }
    }
  }

  return null;
};

/**
 * Resolves a locale string (e.g. 'pt_BR') to a BCP-47 tag Intl APIs accept.
 * @param {string} locale
 * @returns {string}
 */
const resolveIntlLocale = locale => (locale || 'en').replace(/_/g, '-');

/**
 * Formats a date into locale-aware date/time parts for the quoted email header.
 * @param {Date} date - Date to format
 * @param {string} locale - Active UI locale (e.g. 'en', 'pt_BR')
 * @returns {{ date: string, time: string }}
 */
export const formatQuotedEmailDateParts = (date, locale) => {
  const intlLocale = resolveIntlLocale(locale);
  return {
    date: new Intl.DateTimeFormat(intlLocale, {
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    }).format(date),
    time: new Intl.DateTimeFormat(intlLocale, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(date),
  };
};

/**
 * Extracts inbox email address from last email message
 * @param {Object} lastEmail - Last email message object
 * @param {Object} inbox - Inbox object
 * @returns {string} Inbox email address
 */
export const getInboxEmail = (lastEmail, inbox) => {
  const contentAttributes =
    lastEmail?.contentAttributes || lastEmail?.content_attributes || {};
  const emailMeta = contentAttributes.email || {};

  if (Array.isArray(emailMeta.to) && emailMeta.to.length > 0) {
    const toAddress = emailMeta.to[0];
    if (toAddress && toAddress.trim()) {
      return toAddress.trim();
    }
  }

  const inboxEmail = inbox?.email;
  return inboxEmail && inboxEmail.trim() ? inboxEmail.trim() : '';
};

/**
 * Builds quoted email header from contact (for incoming messages)
 * @param {Object} lastEmail - Last email message object
 * @param {Object} contact - Contact object
 * @param {Object} i18nContext - { t, locale }
 * @returns {string} Formatted header string
 */
export const buildQuotedEmailHeaderFromContact = (
  lastEmail,
  contact,
  { t, locale } = {}
) => {
  if (!lastEmail) {
    return '';
  }

  const quotedDate = getEmailDate(lastEmail);
  const senderEmail = getEmailSenderEmail(lastEmail, contact);

  if (!quotedDate || !senderEmail) {
    return '';
  }

  const senderName = getEmailSenderName(lastEmail, contact);
  const hasName = !!senderName;
  const contactLabel = hasName
    ? `${senderName} <${senderEmail}>`
    : `<${senderEmail}>`;

  const { date, time } = formatQuotedEmailDateParts(quotedDate, locale);
  return t('CONVERSATION.REPLYBOX.QUOTED_REPLY.HEADER', {
    date,
    time,
    contact: contactLabel,
  });
};

/**
 * Builds quoted email header from inbox (for outgoing messages)
 * @param {Object} lastEmail - Last email message object
 * @param {Object} inbox - Inbox object
 * @param {Object} i18nContext - { t, locale }
 * @returns {string} Formatted header string
 */
export const buildQuotedEmailHeaderFromInbox = (
  lastEmail,
  inbox,
  { t, locale } = {}
) => {
  if (!lastEmail) {
    return '';
  }

  const quotedDate = getEmailDate(lastEmail);
  const inboxEmail = getInboxEmail(lastEmail, inbox);

  if (!quotedDate || !inboxEmail) {
    return '';
  }

  const inboxName = inbox?.name;
  const hasName = !!inboxName;
  const inboxLabel = hasName
    ? `${inboxName} <${inboxEmail}>`
    : `<${inboxEmail}>`;

  const { date, time } = formatQuotedEmailDateParts(quotedDate, locale);
  return t('CONVERSATION.REPLYBOX.QUOTED_REPLY.HEADER', {
    date,
    time,
    contact: inboxLabel,
  });
};

/**
 * Builds quoted email header based on message type
 * @param {Object} lastEmail - Last email message object
 * @param {Object} contact - Contact object
 * @param {Object} inbox - Inbox object
 * @param {Object} i18nContext - { t, locale } used to build a locale-aware header
 * @returns {string} Formatted header string
 */
export const buildQuotedEmailHeader = (
  lastEmail,
  contact,
  inbox,
  i18nContext = {}
) => {
  if (!lastEmail) {
    return '';
  }

  // MESSAGE_TYPE.OUTGOING = 1, MESSAGE_TYPE.INCOMING = 0
  const isOutgoing = lastEmail.message_type === 1;

  if (isOutgoing) {
    return buildQuotedEmailHeaderFromInbox(lastEmail, inbox, i18nContext);
  }

  return buildQuotedEmailHeaderFromContact(lastEmail, contact, i18nContext);
};

/**
 * Formats text as a markdown blockquote, with an optional header rendered as
 * a plain line before the blockquote (Gmail-style) rather than inside it.
 * @param {string} text - Text to format
 * @param {string} header - Optional header to prepend, outside the blockquote
 * @returns {string} Formatted header + blockquote
 */
export const formatQuotedTextAsBlockquote = (text, header = '') => {
  const normalizedLines = text
    ? String(text).replace(/\r\n/g, '\n').split('\n')
    : [];

  const quotedBody = normalizedLines
    .map(line => {
      const trimmedLine = line.trimEnd();
      return trimmedLine ? `> ${trimmedLine}` : '>';
    })
    .join('\n');

  if (!header) {
    return quotedBody;
  }
  if (!quotedBody) {
    return header;
  }

  return `${header}\n\n${quotedBody}`;
};

const BLOCK_LEVEL_TAGS = new Set([
  'P',
  'DIV',
  'TR',
  'TABLE',
  'LI',
  'UL',
  'OL',
  'H1',
  'H2',
  'H3',
  'H4',
  'H5',
  'H6',
  'SECTION',
  'ARTICLE',
]);

/**
 * Converts HTML into quoted markdown, preserving `<blockquote>` nesting depth
 * (each ancestor blockquote adds one more `>` prefix) and paragraph/block-level
 * breaks. Used when re-quoting a stored email's HTML content so that a chain
 * of replies-to-replies keeps its full hierarchy intact.
 * @param {string} html - HTML content to convert
 * @returns {string} Quoted markdown
 */
export const convertQuotedHtmlToMarkdown = html => {
  if (!html) {
    return '';
  }
  if (typeof document === 'undefined') {
    return extractPlainTextFromHtml(html);
  }

  const container = document.createElement('div');
  container.innerHTML = DOMPurify.sanitize(html);

  const lines = [];
  let currentLine = '';
  let pendingBreakDepth = null; // a separator owed at this depth, before the next real content
  let brRunCount = 0; // consecutive <br> siblings seen but not yet resolved

  // Mirrors formatQuotedTextAsBlockquote's own single-level convention
  // (content line: '> ' + text; blank continuation line: bare '>') applied
  // `depth` times, so re-wrapping this output nests correctly: '> '.repeat(n)
  // for content, and '> '.repeat(n - 1) + '>' for a blank continuation line.
  const emitPendingBreak = () => {
    if (pendingBreakDepth === null) {
      return;
    }
    const depth = pendingBreakDepth;
    lines.push(depth > 0 ? `${'> '.repeat(depth - 1)}>` : '');
    pendingBreakDepth = null;
  };

  const flushContent = depth => {
    if (!currentLine.trim()) {
      currentLine = '';
      return;
    }
    emitPendingBreak();
    lines.push(`${'> '.repeat(depth)}${currentLine.trim()}`);
    currentLine = '';
  };

  // A single <br> is just a line break within the same paragraph (flush the
  // preceding text as its own line, nothing more). Two or more consecutive
  // <br> siblings are Gmail/Outlook's convention for a paragraph gap — treat
  // any run of 2+ as exactly one paragraph break, never stacking multiple
  // blank lines for 3+. Must be resolved before any other node is processed,
  // since <br> siblings only accumulate a count as they're walked.
  const resolveBrRun = depth => {
    if (brRunCount === 0) {
      return;
    }
    flushContent(depth);
    if (brRunCount >= 2 && lines.length) {
      pendingBreakDepth = depth;
    }
    brRunCount = 0;
  };

  const walk = (node, depth) => {
    if (node.nodeType === Node.TEXT_NODE) {
      resolveBrRun(depth);
      currentLine += node.textContent;
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return;
    }

    if (node.tagName === 'BR') {
      brRunCount += 1;
      return;
    }

    resolveBrRun(depth);

    const isBlockquote = node.tagName === 'BLOCKQUOTE';
    const isBlock = isBlockquote || BLOCK_LEVEL_TAGS.has(node.tagName);
    const childDepth = isBlockquote ? depth + 1 : depth;

    if (isBlock) {
      flushContent(depth);
    }
    node.childNodes.forEach(child => walk(child, childDepth));
    if (isBlock) {
      resolveBrRun(childDepth);
      flushContent(childDepth);
      // owe a separator at `depth` before whatever sibling content comes
      // next; discarded harmlessly if nothing ever follows
      if (lines.length) {
        pendingBreakDepth = depth;
      }
    }
  };

  container.childNodes.forEach(node => walk(node, 0));
  resolveBrRun(0);
  flushContent(0);

  return lines.join('\n');
};

/**
 * Extracts quoted email text from last email message
 * @param {Object} lastEmail - Last email message object
 * @returns {string} Quoted email text
 */
export const extractQuotedEmailText = lastEmail => {
  if (!lastEmail) {
    return '';
  }

  const contentAttributes =
    lastEmail.contentAttributes || lastEmail.content_attributes || {};
  const emailContent = contentAttributes.email || {};
  const textContent = emailContent.textContent || emailContent.text_content;

  // Prefer `full` over `reply`: for outgoing messages they're identical, but
  // for inbound HTML-only emails `reply` has nested blockquotes collapsed to
  // a bare marker (content discarded), while `full` retains everything.
  if (textContent?.full) {
    return textContent.full;
  }
  if (textContent?.reply) {
    return textContent.reply;
  }

  const htmlContent = emailContent.htmlContent || emailContent.html_content;
  if (htmlContent?.full) {
    return convertQuotedHtmlToMarkdown(htmlContent.full);
  }
  if (htmlContent?.reply) {
    return convertQuotedHtmlToMarkdown(htmlContent.reply);
  }

  const fallbackContent =
    lastEmail.content || lastEmail.processed_message_content || '';

  return fallbackContent;
};

/**
 * Truncates text for preview display
 * @param {string} text - Text to truncate
 * @param {number} maxLength - Maximum length (default: 80)
 * @returns {string} Truncated text
 */
export const truncatePreviewText = (text, maxLength = 80) => {
  const preview = text.trim().replace(/\s+/g, ' ');
  if (!preview) {
    return '';
  }

  if (preview.length <= maxLength) {
    return preview;
  }
  return `${preview.slice(0, maxLength - 3)}...`;
};

/**
 * Appends quoted text to message
 * @param {string} message - Original message
 * @param {string} quotedText - Text to quote
 * @param {string} header - Quote header
 * @returns {string} Message with quoted text appended
 */
export const appendQuotedTextToMessage = (message, quotedText, header) => {
  const baseMessage = message ? String(message) : '';
  const quotedBlock = formatQuotedTextAsBlockquote(quotedText, header);

  if (!quotedBlock) {
    return baseMessage;
  }

  if (!baseMessage) {
    return quotedBlock;
  }

  let separator = '\n\n';
  if (baseMessage.endsWith('\n\n')) {
    separator = '';
  } else if (baseMessage.endsWith('\n')) {
    separator = '\n';
  }

  return `${baseMessage}${separator}${quotedBlock}`;
};
