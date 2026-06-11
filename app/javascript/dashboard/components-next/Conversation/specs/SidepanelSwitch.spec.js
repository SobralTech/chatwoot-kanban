import { shallowMount } from '@vue/test-utils';

import SidepanelSwitch from '../SidepanelSwitch.vue';

const mocks = vi.hoisted(() => ({
  isCaptainEnabled: true,
  uiSettings: {
    value: {
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    },
  },
  updateUISettings: vi.fn(),
  useKeyboardEvents: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: mocks.uiSettings,
    updateUISettings: mocks.updateUISettings,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    const getters = {
      getCurrentAccountId: {
        value: 1,
      },
      'accounts/isFeatureEnabledonAccount': {
        value: () => mocks.isCaptainEnabled,
      },
    };

    return getters[key];
  },
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: mocks.useKeyboardEvents,
}));

const ButtonStub = {
  props: ['icon'],
  template: '<button :data-icon="icon" @click="$emit(\'click\')" />',
};

const ButtonGroupStub = {
  template: '<div data-testid="sidepanel-switch"><slot /></div>',
};

const mountSwitch = () =>
  shallowMount(SidepanelSwitch, {
    global: {
      mocks: {
        $t: key => key,
      },
      directives: {
        tooltip: {},
      },
      stubs: {
        Button: ButtonStub,
        ButtonGroup: ButtonGroupStub,
      },
    },
  });

describe('SidepanelSwitch', () => {
  beforeEach(() => {
    mocks.isCaptainEnabled = true;
    mocks.uiSettings.value = {
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    };
    mocks.updateUISettings.mockClear();
    mocks.useKeyboardEvents.mockClear();
  });

  it('does not render the floating contact profile button', () => {
    const wrapper = mountSwitch();

    expect(wrapper.find('[data-icon="i-ph-user-bold"]').exists()).toBe(false);
  });

  it('keeps the copilot sidepanel button functional', async () => {
    const wrapper = mountSwitch();

    await wrapper.get('[data-icon="i-woot-captain"]').trigger('click');

    expect(mocks.updateUISettings).toHaveBeenCalledWith({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: true,
    });
  });

  it('does not render an empty floating switch when no sidepanel buttons remain', () => {
    mocks.isCaptainEnabled = false;
    const wrapper = mountSwitch();

    expect(wrapper.find('[data-testid="sidepanel-switch"]').exists()).toBe(
      false
    );
  });
});
