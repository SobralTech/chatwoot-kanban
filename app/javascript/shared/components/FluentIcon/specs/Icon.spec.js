import { mount } from '@vue/test-utils';
import DashboardIcon from '../DashboardIcon.vue';

describe('DashboardIcon (fluent-icon)', () => {
  it('renders a known icon without throwing', () => {
    expect(() =>
      mount(DashboardIcon, { props: { icon: 'archive' } })
    ).not.toThrow();
  });

  it('does not crash the render tree when the icon key does not exist in the icon set', () => {
    // Regression: a typo'd/removed icon name used to throw
    // "Cannot read properties of undefined (reading 'constructor')" inside the
    // pathSource computed, which broke the whole context menu render (see the
    // Conversations context menu archive/unarchive regression).
    let wrapper;
    expect(() => {
      wrapper = mount(DashboardIcon, { props: { icon: 'does-not-exist' } });
    }).not.toThrow();
    expect(wrapper.findAll('path')).toHaveLength(0);
  });
});
