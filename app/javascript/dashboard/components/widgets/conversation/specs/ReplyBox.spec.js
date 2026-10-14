import { shallowMount } from '@vue/test-utils';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { nextTick } from 'vue';
import { createStore } from 'vuex';
import ReplyBox from '../ReplyBox.vue';
import WhatsappTemplates from '../WhatsappTemplates/Modal.vue';

vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return { useAccount: () => ({ currentAccount: ref({}) }) };
});

const CHANNELS = [
  { name: 'WhatsApp Cloud', inbox: { channel_type: 'Channel::Whatsapp' } },
  {
    name: 'Twilio WhatsApp',
    inbox: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
  },
  { name: 'API', inbox: { channel_type: 'Channel::Api' } },
  { name: 'Instagram', inbox: { channel_type: 'Channel::Instagram' } },
  { name: 'TikTok', inbox: { channel_type: 'Channel::Tiktok' } },
  { name: 'Facebook', inbox: { channel_type: 'Channel::FacebookPage' } },
  { name: 'Line', inbox: { channel_type: 'Channel::Line' } },
  { name: 'Telegram', inbox: { channel_type: 'Channel::Telegram' } },
  { name: 'Email', inbox: { channel_type: 'Channel::Email' } },
  { name: 'Web widget', inbox: { channel_type: 'Channel::WebWidget' } },
];

const exemptFromMessagingWindow = name =>
  ['WhatsApp Cloud', 'Twilio WhatsApp', 'API'].includes(name);

const REPLIABLE = {
  id: 1,
  inbox_id: 1,
  can_reply: true,
  status: 'open',
  meta: { sender: { id: 2 } },
  messages: [],
};

const buildStore = ({
  inbox,
  chat,
  templates,
  drafts = {},
  inboxes,
  isMetaMessageSendingDisabled = false,
}) =>
  createStore({
    state: {
      chat: { ...REPLIABLE, ...chat },
      replyEditorMode: REPLY_EDITOR_MODES.REPLY,
      drafts: { ...drafts },
    },
    mutations: {
      selectChat: (s, c) => {
        s.chat = c;
      },
      setReplyEditorMode: (s, mode) => {
        s.replyEditorMode = mode;
      },
      setDraft: (s, { key, message }) => {
        s.drafts = { ...s.drafts, [key]: message };
      },
    },
    actions: {
      'draftMessages/setReplyEditorMode': ({ commit }, { mode }) =>
        commit('setReplyEditorMode', mode),
      'draftMessages/set': ({ commit }, payload) => commit('setDraft', payload),
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: 7, name: 'Agent', accounts: [] }),
      getCurrentAccountId: () => 1,
      getMessageSignature: () => '',
      getUISettings: () => ({}),
      getLastEmailInSelectedChat: () => null,
      'globalConfig/get': () => ({}),
      'globalConfig/isMetaMessageSendingDisabled': () =>
        isMetaMessageSendingDisabled,
      'inboxes/getInbox': () => inboxId => ({
        id: inboxId,
        ...(inboxes?.[inboxId] || inbox),
      }),
      'inboxes/getWhatsAppTemplates': () => () => templates,
      'contacts/getContact': () => () => ({}),
      'draftMessages/get': s => key => s.drafts[key] || '',
      'draftMessages/getReplyEditorMode': s => s.replyEditorMode,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'accounts/getAccount': () => () => ({}),
      'portals/allPortals': () => [],
      'integrations/getUIFlags': () => ({ isFetching: false }),
    },
  });

const mountWith = ({
  inbox,
  chat,
  templates = [{ name: 'greeting' }],
  drafts,
  inboxes,
  isMetaMessageSendingDisabled,
}) => {
  const store = buildStore({
    inbox,
    chat,
    templates,
    drafts,
    inboxes,
    isMetaMessageSendingDisabled,
  });
  const wrapper = shallowMount(ReplyBox, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      // The bottom panel sits inside a <Transition>, which shallowMount stubs
      // without rendering its children.
      stubs: { transition: false },
      // The single-line composer renders the editor inside the bottom panel slot.
      renderStubDefaultSlot: true,
    },
  });
  return { wrapper, store };
};

const topPanel = wrapper =>
  wrapper.findComponent({ name: 'ReplyTopPanel' }).props();
const bottomPanel = wrapper =>
  wrapper.findComponent({ name: 'ReplyBottomPanel' }).props();
const editor = wrapper =>
  wrapper.findComponent({ name: 'WootMessageEditor' }).props();

describe('ReplyBox', () => {
  describe('Instagram incident restriction', () => {
    it('opens in note mode and restores only the private-note draft', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::Instagram' },
        isMetaMessageSendingDisabled: true,
        drafts: {
          'draft-1-REPLY': 'unsent public reply',
          'draft-1-NOTE': 'incident note',
        },
      });
      await nextTick();

      expect(topPanel(wrapper).mode).toBe(REPLY_EDITOR_MODES.NOTE);
      expect(topPanel(wrapper).isReplyRestricted).toBe(true);
      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
      expect(editor(wrapper).editorId).toBe('draft-1-NOTE');
      expect(wrapper.vm.message).toBe('incident note');
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
      expect(store.getters['draftMessages/get']('draft-1-REPLY')).toBe(
        'unsent public reply'
      );
    });

    it('preserves draft ownership when switching to a restricted conversation', async () => {
      const drafts = {
        'draft-1-REPLY': 'conversation A reply',
        'draft-1-NOTE': 'conversation A note',
        'draft-2-REPLY': 'conversation B reply',
        'draft-2-NOTE': 'conversation B note',
      };
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        inboxes: {
          1: { channel_type: 'Channel::WebWidget' },
          2: { channel_type: 'Channel::Instagram' },
        },
        drafts,
        isMetaMessageSendingDisabled: true,
      });
      await nextTick();

      store.commit('selectChat', { ...REPLIABLE, id: 2, inbox_id: 2 });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-2-NOTE',
        modelValue: 'conversation B note',
      });
      Object.entries(drafts).forEach(([key, message]) => {
        expect(store.getters['draftMessages/get'](key)).toBe(message);
      });
    });
  });

  describe.each(CHANNELS)('$name', ({ name, inbox }) => {
    it('locks the composer and hides template sends when a bot owns a pending conversation', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
      });

      expect(topPanel(wrapper).isReplyRestricted).toBe(true);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(false);
      expect(bottomPanel(wrapper).enableContentTemplates).toBe(false);
      // The note composer stays usable — this is a restriction, not a lockout.
      expect(topPanel(wrapper).isEditorDisabled).toBe(false);
    });

    it('opens directly in note mode when a bot already owns the pending conversation', () => {
      const { wrapper, store } = mountWith({
        inbox,
        chat: {
          can_reply: false,
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
      expect(topPanel(wrapper).isEditorDisabled).toBe(false);
    });

    it('opens in reply mode for every other conversation', () => {
      const { wrapper, store } = mountWith({ inbox });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.REPLY
      );
    });

    it.each(['open', 'resolved', 'snoozed'])(
      'leaves the composer open when a bot owns a %s conversation',
      status => {
        const { wrapper } = mountWith({
          inbox,
          chat: {
            status,
            meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
          },
        });

        expect(topPanel(wrapper).isReplyRestricted).toBe(false);
        expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(true);
      }
    );

    it('leaves the composer open when a human owns a pending conversation', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'User' },
        },
      });

      expect(topPanel(wrapper).isReplyRestricted).toBe(false);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(true);
    });

    it('matches the existing messaging-window rule when no bot is involved', () => {
      const { wrapper } = mountWith({
        inbox,
        chat: { can_reply: false, status: 'resolved' },
      });

      const stillRepliable = exemptFromMessagingWindow(name);
      expect(topPanel(wrapper).isReplyRestricted).toBe(!stillRepliable);
      expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(stillRepliable);
      // WhatsApp/API disable the editor and steer to templates; everywhere
      // else the composer falls back to a usable private note.
      expect(topPanel(wrapper).isEditorDisabled).toBe(stillRepliable);
    });
  });

  it('hides the template action when the inbox has no templates synced', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::Whatsapp' },
      chat: { can_reply: false, status: 'open' },
      templates: [],
    });

    expect(bottomPanel(wrapper).enableWhatsAppTemplates).toBe(false);
    expect(topPanel(wrapper).isReplyRestricted).toBe(false);
  });

  describe('drafts', () => {
    const DRAFTS = {
      'draft-1-REPLY': 'half typed reply',
      'draft-1-NOTE': 'a note',
    };

    it('loads the note draft while a bot owns the conversation', async () => {
      const { wrapper } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
        drafts: DRAFTS,
      });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-1-NOTE',
        modelValue: 'a note',
      });
    });

    it('leaves the saved reply draft intact and restores it on takeover', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
        chat: {
          status: 'pending',
          meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
        },
        drafts: DRAFTS,
      });
      await nextTick();
      expect(store.getters['draftMessages/get']('draft-1-REPLY')).toBe(
        'half typed reply'
      );

      store.commit('selectChat', {
        ...REPLIABLE,
        status: 'open',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });
      await nextTick();

      expect(editor(wrapper)).toMatchObject({
        editorId: 'draft-1-REPLY',
        modelValue: 'half typed reply',
      });
    });
  });

  it('offers content templates on Twilio WhatsApp when no bot owns the conversation', () => {
    const { wrapper } = mountWith({
      inbox: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
      chat: { can_reply: true, status: 'open' },
    });

    expect(bottomPanel(wrapper).enableContentTemplates).toBe(true);
  });

  describe('on selecting a conversation', () => {
    const selectChat = async chat => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::WebWidget' },
      });
      store.commit('selectChat', { ...REPLIABLE, id: 99, ...chat });
      await nextTick();
      return { wrapper, store };
    };

    it('switches to note mode when a bot owns a pending conversation', async () => {
      const { wrapper } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
    });

    it('stays in reply mode when a human owns a pending conversation', async () => {
      const { wrapper } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
    });

    it('closes an open template modal when a bot takes over the conversation', async () => {
      const { wrapper, store } = mountWith({
        inbox: { channel_type: 'Channel::Whatsapp' },
      });
      wrapper
        .findComponent({ name: 'ReplyBottomPanel' })
        .vm.$emit('selectWhatsappTemplate');
      await nextTick();
      expect(wrapper.findComponent(WhatsappTemplates).props('show')).toBe(true);

      store.commit('selectChat', {
        ...REPLIABLE,
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });
      await nextTick();

      expect(wrapper.findComponent(WhatsappTemplates).props('show')).toBe(
        false
      );
    });

    it('returns to reply mode once the agent takes over', async () => {
      const { wrapper, store } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });
      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);

      store.commit('selectChat', {
        ...REPLIABLE,
        id: 99,
        status: 'open',
        meta: { sender: { id: 2 }, assignee_type: 'User' },
      });
      await nextTick();

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(false);
      expect(topPanel(wrapper).isReplyRestricted).toBe(false);
      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.REPLY
      );
    });

    it('keeps the agent in note mode after they chose it themselves', async () => {
      const { wrapper } = await selectChat({});
      wrapper
        .findComponent({ name: 'ReplyTopPanel' })
        .vm.$emit('setReplyMode', REPLY_EDITOR_MODES.NOTE);
      await nextTick();

      expect(bottomPanel(wrapper).isOnPrivateNote).toBe(true);
    });

    it('mirrors the forced note mode into the draftMessages store', async () => {
      const { store } = await selectChat({
        status: 'pending',
        meta: { sender: { id: 2 }, assignee_type: 'AgentBot' },
      });

      expect(store.getters['draftMessages/getReplyEditorMode']).toBe(
        REPLY_EDITOR_MODES.NOTE
      );
    });
  });
});

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
