import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';

import LabelBox from '../LabelBox.vue';

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: false }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

const createWrapper = () => {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ id: 1 }),
    },
    modules: {
      labels: {
        namespaced: true,
        getters: {
          getLabels: () => [
            { id: 1, title: 'billing', color: '#0f0' },
            { id: 2, title: 'vip', color: '#00f' },
          ],
        },
      },
      conversationLabels: {
        namespaced: true,
        getters: {
          getConversationLabels: () => () => ['billing', 'vip'],
          getUIFlags: () => ({ isFetching: false }),
        },
      },
    },
  });

  return shallowMount(LabelBox, {
    props: { compact: true },
    global: {
      plugins: [store],
      directives: {
        OnClickaway: vi.fn(),
        Tooltip: vi.fn(),
      },
      stubs: {
        NextButton: {
          name: 'NextButton',
          props: ['icon', 'label', 'size'],
          template: '<button />',
        },
        'woot-label': true,
        LabelDropdown: {
          name: 'LabelDropdown',
          props: ['createModalSize'],
          template: '<div />',
        },
        AddLabel: true,
        Spinner: true,
      },
    },
  });
};

describe('LabelBox', () => {
  it('shows the active label count and opens its selector below the header', async () => {
    const wrapper = createWrapper();
    wrapper.vm.toggleLabels();
    await wrapper.vm.$nextTick();

    expect(wrapper.getComponent({ name: 'NextButton' }).props()).toMatchObject({
      icon: 'i-lucide-tag',
      label: 2,
      size: 'sm',
    });
    expect(wrapper.find('.right-0.top-8.w-80').exists()).toBe(true);
  });
});
