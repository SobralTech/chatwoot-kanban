import { mount } from '@vue/test-utils';
import MessageStatus from '../MessageStatus.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('MessageStatus', () => {
  it.each([
    ['sent', 'i-lucide-check'],
    ['delivered', 'i-lucide-check-check'],
    ['read', 'i-lucide-check-check'],
  ])('shows the %s delivery state once', (status, icon) => {
    const wrapper = mount(MessageStatus, {
      props: { status },
      global: {
        stubs: { Icon: { template: '<i :class="icon" />', props: ['icon'] } },
      },
    });

    expect(wrapper.find('i').classes()).toContain(icon);
    expect(wrapper.findAll('i')).toHaveLength(1);
  });

  it('keeps delivered and read visually distinct while sharing the double-check icon', () => {
    const mountStatus = status =>
      mount(MessageStatus, {
        props: { status },
        global: {
          stubs: {
            Icon: {
              template: '<i :class="[icon, $attrs.class]" />',
              props: ['icon'],
            },
          },
        },
      });
    const delivered = mountStatus('delivered').find('i');
    const read = mountStatus('read').find('i');

    expect(delivered.classes()).toContain('i-lucide-check-check');
    expect(read.classes()).toContain('i-lucide-check-check');
    expect(delivered.classes()).toContain('text-n-slate-10');
    expect(read.classes()).toContain('text-[#7EB6FF]');
    expect(delivered.classes()).not.toContain('text-[#7EB6FF]');
    expect(read.classes()).not.toContain('text-n-slate-10');
  });

  it('keeps a failed message in the error state without a delivery check', () => {
    const wrapper = mount(MessageStatus, {
      props: { status: 'failed' },
      global: {
        stubs: { Icon: { template: '<i :class="icon" />', props: ['icon'] } },
      },
    });

    expect(wrapper.find('i').classes()).toContain('i-lucide-circle-alert');
    expect(wrapper.find('i').classes()).not.toContain('i-lucide-check');
  });
});
