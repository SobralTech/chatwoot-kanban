import {
  extractPlainTextFromHtml,
  getEmailSenderName,
  getEmailSenderEmail,
  getEmailDate,
  formatQuotedEmailDateParts,
  getInboxEmail,
  buildQuotedEmailHeader,
  buildQuotedEmailHeaderFromContact,
  buildQuotedEmailHeaderFromInbox,
  formatQuotedTextAsBlockquote,
  extractQuotedEmailText,
  convertQuotedHtmlToMarkdown,
  truncatePreviewText,
  appendQuotedTextToMessage,
} from '../quotedEmailHelper';

// Fake `t` shaped like the en/pt_BR CONVERSATION.REPLYBOX.QUOTED_REPLY.HEADER
// translation keys, so tests prove the header text is fully driven by i18n
// rather than any hardcoded string in the helper.
const enFakeT = (key, params) =>
  `On ${params.date} at ${params.time} ${params.contact} wrote:`;
const ptFakeT = (key, params) =>
  `Em ${params.date} às ${params.time}, ${params.contact} escreveu:`;

// Copied verbatim (HTML only) from the real Gmail-shaped fixture at
// app/javascript/dashboard/components-next/message/fixtures/emailConversation.js
// (message id 60917) — used to validate re-quoting against actual Gmail markup
// (gmail_quote_container / gmail_attr / blockquote.gmail_quote), not a
// synthetic approximation.
const GMAIL_FIXTURE_HTML =
  '<div dir="ltr">Great we were looking for something in a different finish see image attached<br><br><img src="https://staging.chatwoot.com/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBdGlKIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--408309fa40f1cfea87ee3320a062a5d16ce09d4e/image.png" alt="image.png" width="472" height="305"><br><div><br></div><div>Let me know if you have different finish options?<br><br>Best Regards</div></div><br><div class="gmail_quote gmail_quote_container"><div dir="ltr" class="gmail_attr">On Wed, 4 Dec 2024 at 17:17, Sam from CottonMart &lt;<a href="mailto:sam@cottonmart.test">sam@cottonmart.test</a>&gt; wrote:<br></div><blockquote class="gmail_quote" style="margin:0px 0px 0px 0.8ex;border-left:1px solid rgb(204,204,204);padding-left:1ex">  <p>Dear Alex,</p>\n<p>Please find attached images of our cotton fabric samples. Let us know if you\'d like physical samples sent to you.</p>\n<p>Warm regards,<br>\nSam</p>\n\n    attachment [<a href="https://staging.chatwoot.com/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsibWVzc2FnZSI6IkJBaHBBdGVKIiwiZXhwIjpudWxsLCJwdXIiOiJibG9iX2lkIn19--62ee3b99421bfe7d8db85959ae99ab03a899f351/image.png" target="_blank">click here to view</a>]\n</blockquote></div>\n';

describe('quotedEmailHelper', () => {
  describe('extractPlainTextFromHtml', () => {
    it('returns empty string for null or undefined', () => {
      expect(extractPlainTextFromHtml(null)).toBe('');
      expect(extractPlainTextFromHtml(undefined)).toBe('');
    });

    it('strips HTML tags and returns plain text', () => {
      const html = '<p>Hello <strong>world</strong></p>';
      const result = extractPlainTextFromHtml(html);
      expect(result).toBe('Hello world');
    });

    it('handles complex HTML structure', () => {
      const html = '<div><p>Line 1</p><p>Line 2</p></div>';
      const result = extractPlainTextFromHtml(html);
      expect(result).toContain('Line 1');
      expect(result).toContain('Line 2');
    });

    it('sanitizes onerror handlers from img tags', () => {
      const html = '<p>Hello</p><img src="x" onerror="alert(1)">';
      const result = extractPlainTextFromHtml(html);
      expect(result).toBe('Hello');
    });

    it('sanitizes script tags', () => {
      const html = '<p>Safe</p><script>alert(1)</script><p>Content</p>';
      const result = extractPlainTextFromHtml(html);
      expect(result).toContain('Safe');
      expect(result).toContain('Content');
      expect(result).not.toContain('alert');
    });

    it('sanitizes onclick handlers', () => {
      const html = '<p onclick="alert(1)">Click me</p>';
      const result = extractPlainTextFromHtml(html);
      expect(result).toBe('Click me');
    });
  });

  describe('getEmailSenderName', () => {
    it('returns sender name from lastEmail', () => {
      const lastEmail = { sender: { name: 'John Doe' } };
      const result = getEmailSenderName(lastEmail, {});
      expect(result).toBe('John Doe');
    });

    it('returns contact name if sender name not available', () => {
      const lastEmail = { sender: {} };
      const contact = { name: 'Jane Smith' };
      const result = getEmailSenderName(lastEmail, contact);
      expect(result).toBe('Jane Smith');
    });

    it('returns empty string if neither available', () => {
      const result = getEmailSenderName({}, {});
      expect(result).toBe('');
    });

    it('trims whitespace from names', () => {
      const lastEmail = { sender: { name: '  John Doe  ' } };
      const result = getEmailSenderName(lastEmail, {});
      expect(result).toBe('John Doe');
    });
  });

  describe('getEmailSenderEmail', () => {
    it('returns sender email from lastEmail', () => {
      const lastEmail = { sender: { email: 'john@example.com' } };
      const result = getEmailSenderEmail(lastEmail, {});
      expect(result).toBe('john@example.com');
    });

    it('returns email from contentAttributes if sender email not available', () => {
      const lastEmail = {
        contentAttributes: {
          email: { from: ['jane@example.com'] },
        },
      };
      const result = getEmailSenderEmail(lastEmail, {});
      expect(result).toBe('jane@example.com');
    });

    it('returns contact email as fallback', () => {
      const lastEmail = {};
      const contact = { email: 'contact@example.com' };
      const result = getEmailSenderEmail(lastEmail, contact);
      expect(result).toBe('contact@example.com');
    });

    it('trims whitespace from emails', () => {
      const lastEmail = { sender: { email: '  john@example.com  ' } };
      const result = getEmailSenderEmail(lastEmail, {});
      expect(result).toBe('john@example.com');
    });
  });

  describe('getEmailDate', () => {
    it('returns parsed date from email metadata', () => {
      const lastEmail = {
        contentAttributes: {
          email: { date: '2024-01-15T10:30:00Z' },
        },
      };
      const result = getEmailDate(lastEmail);
      expect(result).toBeInstanceOf(Date);
    });

    it('returns date from created_at timestamp', () => {
      const lastEmail = { created_at: 1705318200 };
      const result = getEmailDate(lastEmail);
      expect(result).toBeInstanceOf(Date);
    });

    it('handles millisecond timestamps', () => {
      const lastEmail = { created_at: 1705318200000 };
      const result = getEmailDate(lastEmail);
      expect(result).toBeInstanceOf(Date);
    });

    it('returns null if no valid date found', () => {
      const result = getEmailDate({});
      expect(result).toBeNull();
    });
  });

  describe('formatQuotedEmailDateParts', () => {
    it('formats date/time using Intl for the given locale', () => {
      const date = new Date('2024-01-15T10:30:00Z');
      const result = formatQuotedEmailDateParts(date, 'en');
      expect(result.date).toMatch(/Jan/);
      expect(result.time).toMatch(/\d{1,2}:\d{2}/);
    });

    it('produces different output for a different locale', () => {
      const date = new Date('2024-01-15T10:30:00Z');
      const en = formatQuotedEmailDateParts(date, 'en');
      const ptBr = formatQuotedEmailDateParts(date, 'pt_BR');
      expect(ptBr.date).not.toBe(en.date);
    });

    it('falls back to en when locale is missing', () => {
      const date = new Date('2024-01-15T10:30:00Z');
      const result = formatQuotedEmailDateParts(date, undefined);
      expect(result.date).toMatch(/Jan/);
    });
  });

  describe('getInboxEmail', () => {
    it('returns email from contentAttributes.email.to', () => {
      const lastEmail = {
        contentAttributes: {
          email: { to: ['inbox@example.com'] },
        },
      };
      const result = getInboxEmail(lastEmail, {});
      expect(result).toBe('inbox@example.com');
    });

    it('returns inbox email as fallback', () => {
      const lastEmail = {};
      const inbox = { email: 'support@example.com' };
      const result = getInboxEmail(lastEmail, inbox);
      expect(result).toBe('support@example.com');
    });

    it('returns empty string if no email found', () => {
      expect(getInboxEmail({}, {})).toBe('');
    });

    it('trims whitespace from emails', () => {
      const lastEmail = {
        contentAttributes: {
          email: { to: ['  inbox@example.com  '] },
        },
      };
      const result = getInboxEmail(lastEmail, {});
      expect(result).toBe('inbox@example.com');
    });
  });

  describe('buildQuotedEmailHeaderFromContact', () => {
    it('builds complete header with name and email', () => {
      const lastEmail = {
        sender: { name: 'John Doe', email: 'john@example.com' },
        contentAttributes: {
          email: { date: '2024-01-15T10:30:00Z' },
        },
      };
      const result = buildQuotedEmailHeaderFromContact(
        lastEmail,
        {},
        { t: enFakeT, locale: 'en' }
      );
      expect(result).toContain('John Doe');
      expect(result).toContain('john@example.com');
      expect(result).toContain('wrote:');
    });

    it('builds header without name if not available', () => {
      const lastEmail = {
        sender: { email: 'john@example.com' },
        contentAttributes: {
          email: { date: '2024-01-15T10:30:00Z' },
        },
      };
      const result = buildQuotedEmailHeaderFromContact(
        lastEmail,
        {},
        { t: enFakeT, locale: 'en' }
      );
      expect(result).toContain('<john@example.com>');
      expect(result).not.toContain('undefined');
    });

    it('returns empty string if missing required data', () => {
      expect(
        buildQuotedEmailHeaderFromContact(
          null,
          {},
          { t: enFakeT, locale: 'en' }
        )
      ).toBe('');
      expect(
        buildQuotedEmailHeaderFromContact({}, {}, { t: enFakeT, locale: 'en' })
      ).toBe('');
    });

    it('builds the header entirely from the provided t function, not a hardcoded string', () => {
      const lastEmail = {
        sender: { name: 'John Doe', email: 'john@example.com' },
        contentAttributes: {
          email: { date: '2024-01-15T10:30:00Z' },
        },
      };
      const result = buildQuotedEmailHeaderFromContact(
        lastEmail,
        {},
        { t: ptFakeT, locale: 'pt_BR' }
      );
      expect(result).toContain('escreveu:');
      expect(result).not.toContain('wrote:');
      expect(result).toContain('John Doe <john@example.com>');
    });
  });

  describe('buildQuotedEmailHeaderFromInbox', () => {
    it('builds complete header with inbox name and email', () => {
      const lastEmail = {
        contentAttributes: {
          email: {
            date: '2024-01-15T10:30:00Z',
            to: ['support@example.com'],
          },
        },
      };
      const inbox = { name: 'Support Team', email: 'support@example.com' };
      const result = buildQuotedEmailHeaderFromInbox(lastEmail, inbox, {
        t: enFakeT,
        locale: 'en',
      });
      expect(result).toContain('Support Team');
      expect(result).toContain('support@example.com');
      expect(result).toContain('wrote:');
    });

    it('builds header without name if not available', () => {
      const lastEmail = {
        contentAttributes: {
          email: {
            date: '2024-01-15T10:30:00Z',
            to: ['inbox@example.com'],
          },
        },
      };
      const inbox = { email: 'inbox@example.com' };
      const result = buildQuotedEmailHeaderFromInbox(lastEmail, inbox, {
        t: enFakeT,
        locale: 'en',
      });
      expect(result).toContain('<inbox@example.com>');
      expect(result).not.toContain('undefined');
    });

    it('returns empty string if missing required data', () => {
      expect(
        buildQuotedEmailHeaderFromInbox(null, {}, { t: enFakeT, locale: 'en' })
      ).toBe('');
      expect(
        buildQuotedEmailHeaderFromInbox({}, {}, { t: enFakeT, locale: 'en' })
      ).toBe('');
    });
  });

  describe('buildQuotedEmailHeader', () => {
    it('uses inbox email for outgoing messages (message_type: 1)', () => {
      const lastEmail = {
        message_type: 1,
        contentAttributes: {
          email: {
            date: '2024-01-15T10:30:00Z',
            to: ['support@example.com'],
          },
        },
      };
      const inbox = { name: 'Support', email: 'support@example.com' };
      const contact = { name: 'John Doe', email: 'john@example.com' };
      const result = buildQuotedEmailHeader(lastEmail, contact, inbox, {
        t: enFakeT,
        locale: 'en',
      });
      expect(result).toContain('Support');
      expect(result).toContain('support@example.com');
      expect(result).not.toContain('John Doe');
    });

    it('uses contact email for incoming messages (message_type: 0)', () => {
      const lastEmail = {
        message_type: 0,
        sender: { name: 'Jane Smith', email: 'jane@example.com' },
        contentAttributes: {
          email: { date: '2024-01-15T10:30:00Z' },
        },
      };
      const inbox = { name: 'Support', email: 'support@example.com' };
      const contact = { name: 'Jane Smith', email: 'jane@example.com' };
      const result = buildQuotedEmailHeader(lastEmail, contact, inbox, {
        t: enFakeT,
        locale: 'en',
      });
      expect(result).toContain('Jane Smith');
      expect(result).toContain('jane@example.com');
      expect(result).not.toContain('Support');
    });

    it('returns empty string if missing required data', () => {
      expect(
        buildQuotedEmailHeader(null, {}, {}, { t: enFakeT, locale: 'en' })
      ).toBe('');
      expect(
        buildQuotedEmailHeader({}, {}, {}, { t: enFakeT, locale: 'en' })
      ).toBe('');
    });
  });

  describe('formatQuotedTextAsBlockquote', () => {
    it('formats single line text', () => {
      const result = formatQuotedTextAsBlockquote('Hello world');
      expect(result).toBe('> Hello world');
    });

    it('formats multi-line text', () => {
      const text = 'Line 1\nLine 2\nLine 3';
      const result = formatQuotedTextAsBlockquote(text);
      expect(result).toBe('> Line 1\n> Line 2\n> Line 3');
    });

    it('places the header before the blockquote body, not inside it', () => {
      const result = formatQuotedTextAsBlockquote('Hello', 'Header text');
      expect(result).toBe('Header text\n\n> Hello');
    });

    it('handles empty lines correctly', () => {
      const text = 'Line 1\n\nLine 3';
      const result = formatQuotedTextAsBlockquote(text);
      expect(result).toBe('> Line 1\n>\n> Line 3');
    });

    it('returns empty string for empty input', () => {
      expect(formatQuotedTextAsBlockquote('')).toBe('');
      expect(formatQuotedTextAsBlockquote('', '')).toBe('');
    });

    it('returns just the header when there is no body text', () => {
      expect(formatQuotedTextAsBlockquote('', 'Header text')).toBe(
        'Header text'
      );
    });

    it('handles Windows line endings', () => {
      const text = 'Line 1\r\nLine 2';
      const result = formatQuotedTextAsBlockquote(text);
      expect(result).toBe('> Line 1\n> Line 2');
    });
  });

  describe('convertQuotedHtmlToMarkdown', () => {
    it('returns empty string for empty input', () => {
      expect(convertQuotedHtmlToMarkdown('')).toBe('');
    });

    it('converts real nested <blockquote> HTML preserving depth (exact string)', () => {
      const html =
        '<div>B</div><blockquote><div>A</div><blockquote><div>Z</div></blockquote></blockquote>';
      expect(convertQuotedHtmlToMarkdown(html)).toBe('B\n\n> A\n>\n> > Z');
    });

    it('does not manufacture an empty blockquote marker just from entering a new depth', () => {
      const html =
        '<div>B</div><blockquote><div>A</div><blockquote><div>Z</div></blockquote></blockquote>';
      const result = convertQuotedHtmlToMarkdown(html);
      // No stray leading blank/blockquote marker before the first content at
      // any depth — exact-equality above already guards this, this is an
      // explicit regression guard against the "flush break on enter" bug.
      expect(result).not.toContain('>\n\n');
      expect(result.split('\n')[0]).toBe('B');
    });

    it('keeps exact depths after nesting one more level via formatQuotedTextAsBlockquote', () => {
      const html =
        '<div>B</div><blockquote><div>A</div><blockquote><div>Z</div></blockquote></blockquote>';
      const converted = convertQuotedHtmlToMarkdown(html);
      const nested = formatQuotedTextAsBlockquote(converted);
      expect(nested).toBe('> B\n>\n> > A\n> >\n> > > Z');
    });

    it('preserves paragraph breaks at depth 0', () => {
      const html = '<p>Parágrafo 1</p><p>Parágrafo 2</p>';
      expect(convertQuotedHtmlToMarkdown(html)).toBe(
        'Parágrafo 1\n\nParágrafo 2'
      );
    });

    it('preserves paragraph breaks inside a blockquote', () => {
      const html =
        '<blockquote><p>Parágrafo A</p><p>Parágrafo B</p></blockquote>';
      expect(convertQuotedHtmlToMarkdown(html)).toBe(
        '> Parágrafo A\n>\n> Parágrafo B'
      );
    });

    it('keeps the paragraph break intact after nesting one more level', () => {
      const html =
        '<blockquote><p>Parágrafo A</p><p>Parágrafo B</p></blockquote>';
      const converted = convertQuotedHtmlToMarkdown(html);
      const nested = formatQuotedTextAsBlockquote(converted);
      expect(nested).toBe('> > Parágrafo A\n> >\n> > Parágrafo B');
    });

    it('a single <br> is a line break, not a paragraph break', () => {
      expect(convertQuotedHtmlToMarkdown('A<br>B')).toBe('A\nB');
    });

    it('two consecutive <br> preserve a paragraph break', () => {
      expect(convertQuotedHtmlToMarkdown('A<br><br>B')).toBe('A\n\nB');
    });

    it('three or more consecutive <br> normalize to a single paragraph break, not stacked blanks', () => {
      expect(convertQuotedHtmlToMarkdown('A<br><br><br>B')).toBe('A\n\nB');
      expect(convertQuotedHtmlToMarkdown('A<br><br><br><br>B')).toBe('A\n\nB');
    });

    it('preserves a <br><br> paragraph break inside a blockquote, depth-aware', () => {
      expect(
        convertQuotedHtmlToMarkdown('<blockquote>A<br><br>B</blockquote>')
      ).toBe('> A\n>\n> B');
    });

    it('keeps the <br><br> paragraph break intact after nesting one more level', () => {
      const converted = convertQuotedHtmlToMarkdown(
        '<blockquote>A<br><br>B</blockquote>'
      );
      const nested = formatQuotedTextAsBlockquote(converted);
      expect(nested).toBe('> > A\n> >\n> > B');
    });

    it('a single <br> inside a blockquote stays a line break, not a paragraph break', () => {
      expect(
        convertQuotedHtmlToMarkdown('<blockquote>A<br>B</blockquote>')
      ).toBe('> A\n> B');
    });
  });

  describe('extractQuotedEmailText', () => {
    it('extracts text from textContent.reply when full is absent', () => {
      const lastEmail = {
        contentAttributes: {
          email: { textContent: { reply: 'Reply text' } },
        },
      };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toBe('Reply text');
    });

    it('prefers textContent.full over textContent.reply', () => {
      const lastEmail = {
        contentAttributes: {
          email: {
            textContent: { reply: 'Reply only', full: 'Full content' },
          },
        },
      };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toBe('Full content');
    });

    it('falls back to textContent.full when reply is absent', () => {
      const lastEmail = {
        contentAttributes: {
          email: { textContent: { full: 'Full text' } },
        },
      };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toBe('Full text');
    });

    it('extracts from htmlContent and converts to quoted markdown', () => {
      const lastEmail = {
        contentAttributes: {
          email: { htmlContent: { reply: '<p>HTML reply</p>' } },
        },
      };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toBe('HTML reply');
    });

    it('prefers htmlContent.full over htmlContent.reply, preventing nested-quote loss', () => {
      // Simulates HtmlParser.filter_replies! collapsing a nested blockquote
      // in `reply` to a bare marker, while `full` retains the original.
      const lastEmail = {
        contentAttributes: {
          email: {
            htmlContent: {
              reply: '<p>New text</p><p>&gt;</p>',
              full: '<p>New text</p><blockquote><p>Original quoted content</p></blockquote>',
            },
          },
        },
      };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toContain('Original quoted content');
      expect(result).toContain('> Original quoted content');
    });

    it('uses fallback content if structured content not available', () => {
      const lastEmail = { content: 'Fallback content' };
      const result = extractQuotedEmailText(lastEmail);
      expect(result).toBe('Fallback content');
    });

    it('returns empty string for null or missing email', () => {
      expect(extractQuotedEmailText(null)).toBe('');
      expect(extractQuotedEmailText({})).toBe('');
    });

    it('nests an already-quoted synthetic chain one level deeper when quoted again', () => {
      const lastEmail = {
        contentAttributes: {
          email: {
            htmlContent: {
              full: '<div>B text</div><blockquote><div>A text</div><blockquote><div>Z text</div></blockquote></blockquote>',
            },
          },
        },
      };
      const quoted = extractQuotedEmailText(lastEmail);
      const result = formatQuotedTextAsBlockquote(quoted, 'New header');
      expect(result).toBe(
        'New header\n\n> B text\n>\n> > A text\n> >\n> > > Z text'
      );
    });

    it('nests a real Gmail-shaped chain one level deeper when quoted again', () => {
      const lastEmail = {
        contentAttributes: {
          email: { htmlContent: { full: GMAIL_FIXTURE_HTML } },
        },
      };
      const quoted = extractQuotedEmailText(lastEmail);

      // The <br><br> paragraph gap between these two lines in the source
      // HTML must survive as a real blank line in the extracted markdown,
      // not merge into one paragraph.
      expect(quoted).toContain('different finish options?\n\nBest Regards');

      const result = formatQuotedTextAsBlockquote(quoted, 'New header');

      // Same paragraph gap, now depth-aware: a bare '>' continuation line
      // between the two, one level in.
      expect(result).toContain(
        '> Let me know if you have different finish options?\n>\n> Best Regards'
      );

      // B's own newest text ends up at depth 1 (inside the new citation).
      expect(result).toMatch(
        /(^|\n)> Let me know if you have different finish options\?/
      );
      // B's own sign-off ends up at depth 1, inside the citation, not dropped.
      expect(result).toMatch(/(^|\n)> Best Regards/);
      // B's own gmail_attr header (quoting A) ends up at depth 1, not stripped.
      expect(result).toMatch(
        /(^|\n)> On Wed, 4 Dec 2024 at 17:17, Sam from CottonMart/
      );
      // A's message, originally inside blockquote.gmail_quote, ends up at depth 2.
      expect(result).toMatch(/(^|\n)> > Dear Alex,/);

      // Nothing from the chain leaks out as new (depth-0) content — every
      // line after the new header + its separating blank line is quoted.
      const [headerLine, blankLine, ...bodyLines] = result.split('\n');
      expect(headerLine).toBe('New header');
      expect(blankLine).toBe('');
      bodyLines
        .filter(line => line.trim() !== '')
        .forEach(line => expect(line.startsWith('>')).toBe(true));
    });
  });

  describe('truncatePreviewText', () => {
    it('returns full text if under max length', () => {
      const text = 'Short text';
      const result = truncatePreviewText(text, 80);
      expect(result).toBe('Short text');
    });

    it('truncates text exceeding max length', () => {
      const text = 'A'.repeat(100);
      const result = truncatePreviewText(text, 80);
      expect(result).toHaveLength(80);
      expect(result).toContain('...');
    });

    it('collapses multiple spaces', () => {
      const text = 'Text   with    spaces';
      const result = truncatePreviewText(text);
      expect(result).toBe('Text with spaces');
    });

    it('trims whitespace', () => {
      const text = '  Text with spaces  ';
      const result = truncatePreviewText(text);
      expect(result).toBe('Text with spaces');
    });

    it('returns empty string for empty input', () => {
      expect(truncatePreviewText('')).toBe('');
      expect(truncatePreviewText('   ')).toBe('');
    });

    it('uses default max length of 80', () => {
      const text = 'A'.repeat(100);
      const result = truncatePreviewText(text);
      expect(result).toHaveLength(80);
    });
  });

  describe('appendQuotedTextToMessage', () => {
    it('appends quoted text to message, with header outside the blockquote', () => {
      const message = 'My reply';
      const quotedText = 'Original message';
      const header = 'On date sender wrote:';
      const result = appendQuotedTextToMessage(message, quotedText, header);

      expect(result).toContain('My reply');
      expect(result).toContain('On date sender wrote:\n\n> Original message');
      expect(result).not.toContain('> On date sender wrote:');
    });

    it('returns only quoted text if message is empty', () => {
      const result = appendQuotedTextToMessage('', 'Quoted', 'Header');
      expect(result).toBe('Header\n\n> Quoted');
    });

    it('returns message if no quoted text', () => {
      const result = appendQuotedTextToMessage('Message', '', '');
      expect(result).toBe('Message');
    });

    it('handles proper spacing with double newline', () => {
      const result = appendQuotedTextToMessage('Message', 'Quoted', 'Header');
      expect(result).toContain('Message\n\nHeader');
    });

    it('does not add extra newlines if message already ends with newlines', () => {
      const result = appendQuotedTextToMessage(
        'Message\n\n',
        'Quoted',
        'Header'
      );
      expect(result).not.toContain('\n\n\n');
    });

    it('adds single newline if message ends with one newline', () => {
      const result = appendQuotedTextToMessage('Message\n', 'Quoted', 'Header');
      expect(result).toBe('Message\n\nHeader\n\n> Quoted');
    });
  });
});
