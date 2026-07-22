import ReplyBox from '../ReplyBox.vue';

// These tests exercise ReplyBox's `getMessageWithQuotedEmailText` and
// `toggleSignatureForDraft` methods in isolation, without mounting the full
// component tree (which pulls in many unrelated mixins/composables/child
// components). Each method's own dependencies are stubbed on a plain context
// object and the *actual* exported method implementations are invoked via
// `.call(context, ...)` — this is the real signature/quote-ordering logic
// under test, not a reimplementation of it.

const { getMessageWithQuotedEmailText, toggleSignatureForDraft } =
  ReplyBox.methods;

const fakeT = (key, params) =>
  `On ${params.date} at ${params.time} ${params.contact} wrote:`;

const baseQuoteContext = (overrides = {}) => ({
  shouldIncludeQuotedEmail: () => true,
  channelType: 'Channel::Email',
  inbox: { medium: '' },
  isSignatureEnabledForInbox: true,
  isSignatureAvailable: true,
  messageSignature: 'Pedro\nSobralTec',
  quotedEmailText: 'Original quoted text',
  currentContact: {},
  lastEmailWithQuotedContent: {
    message_type: 0,
    sender: { name: 'Alex', email: 'alex@example.com' },
    contentAttributes: { email: { date: '2024-01-15T10:30:00Z' } },
  },
  $t: fakeT,
  $i18n: { locale: 'en' },
  ...overrides,
});

describe('ReplyBox getMessageWithQuotedEmailText', () => {
  it('orders the composed message as [message][quote][signature], not [message][signature][quote]', () => {
    const cleanedSignature = 'Pedro\\\nSobralTec'; // canonical form after cleanSignature's hardbreak encoding
    const message = `Hello there\n\n--\n\n${cleanedSignature}`;
    const context = baseQuoteContext();
    const result = getMessageWithQuotedEmailText.call(context, message);

    const quoteIndex = result.indexOf('> Original quoted text');
    const firstPedroIndex = result.indexOf('Pedro');
    const secondPedroIndex = result.indexOf('Pedro', firstPedroIndex + 1);

    expect(quoteIndex).toBeGreaterThan(-1);
    // signature must appear after the quote block, and only once
    expect(result.lastIndexOf('SobralTec')).toBeGreaterThan(quoteIndex);
    expect(secondPedroIndex).toBe(-1);
  });

  it('does not reintroduce a manually deleted signature, including the delimiter-only remnant', () => {
    const message = 'Hello there\n\n--\n';
    const context = baseQuoteContext();
    const result = getMessageWithQuotedEmailText.call(context, message);

    expect(result).not.toContain('Pedro');
    expect(result).not.toContain('SobralTec');
    expect(result).toContain('> Original quoted text');
  });

  it('preserves a manually edited signature verbatim, positioned after the quote', () => {
    const message = 'Hello there\n--\nPedro\nEquipe SobralTec';
    const context = baseQuoteContext();
    const result = getMessageWithQuotedEmailText.call(context, message);

    const quoteIndex = result.indexOf('> Original quoted text');
    const editedSigIndex = result.indexOf('Equipe SobralTec');

    expect(editedSigIndex).toBeGreaterThan(quoteIndex);
    expect(result).toContain('--\nPedro\nEquipe SobralTec');
    // not duplicated
    expect(result.split('Equipe SobralTec')).toHaveLength(2);
  });

  it('does not duplicate the signature if called twice on the same input', () => {
    const message = 'Hello there\n\n--\n\nPedro\\\nSobralTec';
    const context = baseQuoteContext();
    const result1 = getMessageWithQuotedEmailText.call(context, message);
    const result2 = getMessageWithQuotedEmailText.call(context, message);
    expect(result1).toBe(result2);
    expect(result1.split('SobralTec')).toHaveLength(2);
  });

  it('leaves an unrelated trailing "--" untouched when signature auto-append is disabled', () => {
    const message = 'Texto\n\n--\nConteúdo normal';
    const context = baseQuoteContext({
      isSignatureEnabledForInbox: false,
    });
    const result = getMessageWithQuotedEmailText.call(context, message);

    expect(result).toContain('Texto\n\n--\nConteúdo normal');
    expect(result).toContain('> Original quoted text');
  });
});

describe('ReplyBox toggleSignatureForDraft', () => {
  const baseDraftContext = (overrides = {}) => ({
    isPrivate: false,
    isEditorDisabled: false,
    sendWithSignature: true,
    channelType: 'Channel::Email',
    inbox: { medium: '' },
    isAnEmailChannel: true,
    isSignatureEnabledForInbox: true,
    isSignatureAvailable: true,
    messageSignature: 'Pedro\nSobralTec',
    ...overrides,
  });

  it('does not duplicate a canonical signature already present in the draft', () => {
    const cleanedSignature = 'Pedro\\\nSobralTec';
    const draft = `Mensagem\n\n--\n\n${cleanedSignature}`;
    const context = baseDraftContext();
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toBe(draft);
  });

  it('does not duplicate a manually-edited signature already present in the draft', () => {
    const draft = 'Mensagem\n--\nPedro\nEquipe SobralTec';
    const context = baseDraftContext();
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toBe(draft);
  });

  it('does not resurrect a manually-deleted signature, leaving only the orphan delimiter', () => {
    const draft = 'Mensagem\n\n--\n';
    const context = baseDraftContext();
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toBe(draft);
    expect(result).not.toContain('Pedro');
  });

  it('appends the configured signature to a plain draft with no signature-like tail', () => {
    const draft = 'Mensagem sem assinatura';
    const context = baseDraftContext();
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toContain('Mensagem sem assinatura');
    expect(result).toContain('SobralTec');
  });

  it('leaves an unrelated trailing "--" untouched when sendWithSignature is enabled but no signature is configured', () => {
    const draft = 'Texto\n\n--\nConteúdo normal';
    const context = baseDraftContext({
      isSignatureAvailable: false,
      messageSignature: '',
    });
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toBe(draft);
  });

  it('leaves an unrelated trailing "--" untouched when sendWithSignature is disabled', () => {
    const draft = 'Mensagem\n--\nConteúdo normal';
    const context = baseDraftContext({ sendWithSignature: false });
    const result = toggleSignatureForDraft.call(context, draft);
    expect(result).toBe(draft);
  });

  it('regression: a non-email channel keeps the previous append/remove behavior unchanged', () => {
    // Same edited-signature-shaped draft as the email test above, but for a
    // non-email channel — must take the old, unclassified append/remove path.
    const draft = 'Mensagem\n--\nPedro\nEquipe SobralTec';
    const context = baseDraftContext({
      channelType: 'Channel::Whatsapp',
      isAnEmailChannel: false,
    });
    const result = toggleSignatureForDraft.call(context, draft);
    // Old behavior: appendSignature does not recognize the edited tail as a
    // match, so it appends the canonical signature a second time.
    expect(result).not.toBe(draft);
    expect(result).toContain('Equipe SobralTec');
    expect(result.split('SobralTec')).toHaveLength(3);
  });
});
