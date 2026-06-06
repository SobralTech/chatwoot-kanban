import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';

let routeQuery = {};

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: routeQuery }),
}));

const domPurifyDirective = {
  mounted(el, binding) {
    el.innerHTML = binding.value;
  },
  updated(el, binding) {
    el.innerHTML = binding.value;
  },
};

const createStoreConfig = () =>
  createStore({
    getters: {
      'inboxes/getInbox': () => () => ({}),
      getSelectedChatAttachments: () => [],
    },
  });

const defaultProps = {
  id: 1,
  messageType: 0,
  status: 'sent',
  content: 'Hello billing team',
  contentType: 'text',
  conversationId: 1,
  createdAt: 1710000000,
  currentUserId: 1,
};

const mountMessage = props =>
  mount(Message, {
    props: { ...defaultProps, ...props },
    global: {
      plugins: [createStoreConfig()],
      directives: {
        dompurifyHtml: domPurifyDirective,
      },
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        AttachmentChips: true,
        TranslationToggle: true,
        ContextMenu: true,
        Avatar: true,
      },
    },
    attachTo: document.body,
  });

describe('Message', () => {
  beforeEach(() => {
    routeQuery = {};
    window.HTMLElement.prototype.scrollIntoView = vi.fn();
  });

  afterEach(() => {
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  it('renders highlighted text for loaded matching messages', () => {
    const wrapper = mountMessage({ conversationSearchQuery: 'billing' });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      'billing'
    );
  });

  it('highlights text case-insensitively', () => {
    const wrapper = mountMessage({
      content: 'Hello Billing team',
      conversationSearchQuery: 'billing',
    });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      'Billing'
    );
  });

  it('escapes regex special characters safely', () => {
    const wrapper = mountMessage({
      content: 'Use (test) for regex checks',
      conversationSearchQuery: '(test)',
    });

    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      '(test)'
    );
  });

  it('removes highlight when search query is cleared', async () => {
    const wrapper = mountMessage({ conversationSearchQuery: 'billing' });

    await wrapper.setProps({ conversationSearchQuery: '' });

    expect(wrapper.find('.conversation-search-highlight').exists()).toBe(false);
  });

  it('preserves formatted links while highlighting only text nodes', () => {
    const wrapper = mountMessage({
      content: 'Open https://example.com billing',
      conversationSearchQuery: 'billing',
    });

    expect(wrapper.find('a').exists()).toBe(true);
    expect(wrapper.find('.conversation-search-highlight').text()).toBe(
      'billing'
    );
  });

  it('adds distinct visual state for the active result', () => {
    const wrapper = mountMessage({ activeConversationSearchResultId: 1 });

    expect(wrapper.classes()).toContain('outline-n-amber-6');
  });

  it('scrolls loaded active result into view when active result changes', async () => {
    const scrollIntoView = vi.fn();
    window.HTMLElement.prototype.scrollIntoView = scrollIntoView;
    const wrapper = mountMessage({ activeConversationSearchResultId: null });

    await wrapper.setProps({ activeConversationSearchResultId: 1 });
    await wrapper.vm.$nextTick();

    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: 'smooth',
      block: 'nearest',
    });
  });

  it('does not crash when active result is unloaded', async () => {
    const wrapper = mountMessage({ activeConversationSearchResultId: null });

    await expect(
      wrapper.setProps({ activeConversationSearchResultId: 999 })
    ).resolves.toBeUndefined();
  });

  it('preserves route messageId highlight behavior', async () => {
    routeQuery = { messageId: 1 };
    const wrapper = mountMessage();

    await wrapper.vm.$nextTick();

    expect(wrapper.classes()).toContain('bg-n-alpha-1');
  });
});
