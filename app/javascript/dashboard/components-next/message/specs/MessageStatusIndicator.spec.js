import { mount } from '@vue/test-utils';
import { computed } from 'vue';
import MessageStatusIndicator from '../MessageStatusIndicator.vue';

vi.mock('dashboard/composables/useInbox', () => ({
  useInbox: () => ({
    isAWahaChannel: computed(() => true),
    isAWhatsAppChannel: computed(() => false),
    isATwilioChannel: computed(() => false),
    isAFacebookInbox: computed(() => false),
    isASmsInbox: computed(() => false),
    isATelegramChannel: computed(() => false),
    isATiktokChannel: computed(() => false),
    isAnInstagramChannel: computed(() => false),
    isAnEmailChannel: computed(() => false),
    isAPIInbox: computed(() => false),
    isALineChannel: computed(() => false),
    isAWebWidgetInbox: computed(() => false),
  }),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const mountIndicator = status =>
  mount(MessageStatusIndicator, {
    props: {
      message: {
        message_type: 1,
        status,
        source_id: 'waha-source-1',
      },
    },
    global: {
      stubs: { Icon: { template: '<i :class="icon" />', props: ['icon'] } },
      directives: { tooltip: () => {} },
    },
  });

describe('MessageStatusIndicator', () => {
  it.each([
    ['sent', 'i-lucide-check'],
    ['delivered', 'i-lucide-check-check'],
    ['read', 'i-lucide-check-check'],
  ])(
    'exposes the WAHA %s state for a sourced outgoing message',
    (status, icon) => {
      const wrapper = mountIndicator(status);

      expect(wrapper.find('i').classes()).toContain(icon);
    }
  );

  it('exposes failed as the error state rather than a delivery check', () => {
    const wrapper = mountIndicator('failed');

    expect(wrapper.find('i').classes()).toContain('i-lucide-circle-alert');
  });
});
