import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../../../Message.vue';

let routeQuery = {};

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: routeQuery }),
}));

const createStoreConfig = () =>
  createStore({
    getters: {
      'inboxes/getInbox': () => () => ({}),
      getSelectedChatAttachments: () => [],
    },
  });

const defaultEmailContentAttributes = {
  email: {
    htmlContent: {
      full: `
        <div>
          <p>Hello <strong>billing</strong> team</p>
          <p><a href="https://example.com/support?topic=billing">Open support</a></p>
        </div>
      `,
    },
    textContent: {
      full: 'Hello billing team Open support',
    },
  },
};

const defaultProps = {
  id: 1,
  messageType: 0,
  status: 'sent',
  content: '',
  contentType: 'incoming_email',
  contentAttributes: defaultEmailContentAttributes,
  conversationId: 1,
  createdAt: 1710000000,
  currentUserId: 1,
};

const mountEmailMessage = props =>
  mount(Message, {
    props: { ...defaultProps, ...props },
    global: {
      plugins: [createStoreConfig()],
      stubs: {
        Avatar: true,
        BaseBubble: { template: '<div><slot /></div>' },
        ContextMenu: true,
        EmailMeta: true,
        AttachmentChips: {
          props: ['attachments'],
          template:
            '<div data-test-id="attachments"><span v-for="attachment in attachments" :key="attachment.id">{{ attachment.fileName }}</span></div>',
        },
        TranslationToggle: true,
      },
    },
    attachTo: document.body,
  });

describe('EmailBubble', () => {
  beforeEach(() => {
    routeQuery = {};
    window.HTMLElement.prototype.scrollIntoView = vi.fn();
  });

  afterEach(() => {
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  it('highlights matching email text', () => {
    const wrapper = mountEmailMessage({ conversationSearchQuery: 'billing' });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      'billing'
    );
  });

  it('highlights email text case-insensitively', () => {
    const wrapper = mountEmailMessage({
      conversationSearchQuery: 'billing',
      contentAttributes: {
        email: {
          htmlContent: {
            full: '<p>Hello <strong>Billing</strong> team</p>',
          },
          textContent: {
            full: 'Hello Billing team',
          },
        },
      },
    });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      'Billing'
    );
  });

  it('escapes regex special characters safely in email text', () => {
    const wrapper = mountEmailMessage({
      conversationSearchQuery: '(test)',
      contentAttributes: {
        email: {
          htmlContent: {
            full: '<p>Use (test) for regex checks</p>',
          },
          textContent: {
            full: 'Use (test) for regex checks',
          },
        },
      },
    });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      '(test)'
    );
  });

  it('preserves email links and HTML while highlighting text nodes', () => {
    const wrapper = mountEmailMessage({ conversationSearchQuery: 'support' });
    const link = wrapper.find('a');

    expect(wrapper.find('strong').text()).toBe('billing');
    expect(link.attributes('href')).toBe(
      'https://example.com/support?topic=billing'
    );
    expect(link.find('.conversation-search-highlight').text()).toBe('support');
  });

  it('removes email highlight when search query is cleared', async () => {
    const wrapper = mountEmailMessage({ conversationSearchQuery: 'billing' });

    await wrapper.setProps({ conversationSearchQuery: '' });

    expect(wrapper.find('.conversation-search-highlight').exists()).toBe(false);
  });

  it('does not highlight attachments', () => {
    const wrapper = mountEmailMessage({
      conversationSearchQuery: 'invoice.pdf',
      attachments: [{ id: 1, fileName: 'invoice.pdf', fileType: 'file' }],
    });

    expect(wrapper.find('[data-test-id="attachments"]').text()).toBe(
      'invoice.pdf'
    );
    expect(wrapper.find('.conversation-search-highlight').exists()).toBe(false);
  });
});
