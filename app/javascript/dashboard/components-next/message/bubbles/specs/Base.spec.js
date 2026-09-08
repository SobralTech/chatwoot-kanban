import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import BaseBubble from '../Base.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) =>
      ({
        'CONVERSATION.WAHA_GROUP_SENDER': `${values.name} (${values.phone})`,
        'CONVERSATION.WAHA_GROUP_SENDER_NO_NAME': values.phone,
        'CHAT_LIST.ATTACHMENTS.image.CONTENT': 'Image',
      })[key] || key,
  }),
}));

const mountBubble = ({
  inReplyTo = null,
  contentAttributes = {},
  messageType = 0,
} = {}) =>
  mount(
    {
      components: { BaseBubble },
      setup() {
        provideMessageContext({
          variant: ref('user'),
          orientation: ref('left'),
          inReplyTo: ref(inReplyTo),
          shouldGroupWithNext: ref(false),
          isOwnMessage: ref(false),
          contentAttributes: ref(contentAttributes),
          messageType: ref(messageType),
          status: ref('sent'),
          createdAt: ref(1710000000),
        });
      },
      template:
        '<BaseBubble><span class="message-content">Body</span></BaseBubble>',
    },
    {
      global: {
        stubs: { MessageMeta: true },
        directives: {
          dompurifyHtml: (el, binding) => {
            el.innerHTML = binding.value;
          },
        },
      },
    }
  );

describe('Base message bubble', () => {
  it('keeps the structured group sender label separate from the message body', () => {
    const wrapper = mountBubble({
      contentAttributes: { senderName: 'Ana', participantPhone: '+5511' },
    });

    expect(wrapper.text()).toContain('Ana (+5511)');
    expect(wrapper.find('.message-content').text()).toBe('Body');
    expect(wrapper.find('.message-content').text()).not.toContain('Ana');
  });

  it('renders a snapshot quote as a ghost without a navigation affordance', () => {
    const wrapper = mountBubble({
      inReplyTo: { isGhost: true, authorName: 'Rui', content: 'Original text' },
    });
    const quote = wrapper.find('.bg-n-alpha-black1');

    expect(quote.text()).toContain('Rui');
    expect(quote.text()).toContain('Original text');
    expect(quote.classes()).not.toContain('cursor-pointer');
  });

  it('uses the stored media fallback for a ghost media quote', () => {
    const wrapper = mountBubble({
      inReplyTo: { isGhost: true, mediaType: 'image' },
    });

    expect(wrapper.find('.bg-n-alpha-black1').text()).toContain('Image');
  });
});
