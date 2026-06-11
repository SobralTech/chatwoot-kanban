import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';

import ConversationHeader from '../ConversationHeader.vue';

vi.mock('vue-router', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useRoute: () => ({
      params: {},
      name: 'conversation_through_participating',
    }),
  };
});

vi.mock('@vueuse/core', () => ({
  useElementSize: () => ({
    width: ref(320),
    height: ref(48),
  }),
}));

describe('ConversationHeader', () => {
  let chat;
  let contact;
  let inbox;
  let store;
  let updateUISettings;
  let uiSettings;
  let wrapper;
  let callButtonClick;
  let resolveButtonClick;
  let menuButtonClick;

  const createWrapper = ({
    isContactSidebarOpen = false,
    isCopilotPanelOpen = true,
  } = {}) => {
    uiSettings = {
      is_contact_sidebar_open: isContactSidebarOpen,
      is_copilot_panel_open: isCopilotPanelOpen,
    };
    updateUISettings = vi.fn(({ state }, { uiSettings: nextUISettings }) => {
      state.uiSettings = nextUISettings;
    });
    callButtonClick = vi.fn();
    resolveButtonClick = vi.fn();
    menuButtonClick = vi.fn();

    store = createStore({
      state: {
        uiSettings,
      },
      getters: {
        getSelectedChat: () => chat,
        getCurrentAccountId: () => 1,
        getUISettings: state => state.uiSettings,
      },
      actions: {
        updateUISettings,
      },
      modules: {
        contacts: {
          namespaced: true,
          getters: {
            getContact: () => () => contact,
          },
        },
        inboxes: {
          namespaced: true,
          getters: {
            getInbox: () => () => inbox,
            getInboxes: () => [inbox],
            getInboxById: () => () => inbox,
          },
        },
      },
    });

    wrapper = shallowMount(ConversationHeader, {
      props: {
        chat,
      },
      global: {
        plugins: [store],
        stubs: {
          BackButton: {
            name: 'BackButton',
            template: '<a data-testid="back-button" />',
          },
          Avatar: {
            name: 'Avatar',
            props: ['name', 'src', 'size', 'status'],
            template: '<span data-testid="contact-avatar" />',
          },
          ConversationCallButton: {
            name: 'ConversationCallButton',
            template:
              '<button data-testid="conversation-call-button" @click="onClick" />',
            methods: {
              onClick: callButtonClick,
            },
          },
          FluentIcon: {
            name: 'FluentIcon',
            template: '<span data-testid="fluent-icon" />',
          },
          InboxName: {
            name: 'InboxName',
            template: '<span data-testid="inbox-name" />',
          },
          MoreActions: {
            name: 'MoreActions',
            template: `
              <div>
                <button data-testid="resolve-action-button" @click="onResolve" />
                <button data-testid="more-actions-button" @click="onMenu" />
              </div>
            `,
            methods: {
              onResolve: resolveButtonClick,
              onMenu: menuButtonClick,
            },
          },
          SLACardLabel: {
            name: 'SLACardLabel',
            template: '<span data-testid="sla-card-label" />',
          },
        },
      },
    });

    return wrapper;
  };

  const expectContactSidebarToOpen = callIndex => {
    expect(updateUISettings).toHaveBeenCalledWith(expect.any(Object), {
      uiSettings: {
        is_contact_sidebar_open: true,
        is_copilot_panel_open: false,
      },
    });

    if (callIndex) {
      expect(updateUISettings).toHaveBeenNthCalledWith(
        callIndex,
        expect.any(Object),
        {
          uiSettings: {
            is_contact_sidebar_open: true,
            is_copilot_panel_open: false,
          },
        }
      );
    }
  };

  const expectContactSidebarToClose = callIndex => {
    expect(updateUISettings).toHaveBeenNthCalledWith(
      callIndex,
      expect.any(Object),
      {
        uiSettings: {
          is_contact_sidebar_open: false,
          is_copilot_panel_open: false,
        },
      }
    );
  };

  beforeEach(() => {
    chat = {
      id: 42,
      inbox_id: 7,
      status: 'open',
      meta: {
        sender: { id: 21 },
        hmac_verified: true,
      },
    };
    contact = {
      id: 21,
      name: 'Ada Lovelace',
      thumbnail: 'https://example.com/avatar.png',
      availability_status: 'online',
    };
    inbox = {
      id: 7,
      channel_type: 'Channel::Email',
    };
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  it('renders the contact avatar in the conversation header', () => {
    createWrapper();

    const avatar = wrapper.getComponent({ name: 'Avatar' });

    expect(avatar.props()).toEqual({
      name: 'Ada Lovelace',
      src: 'https://example.com/avatar.png',
      size: 32,
      status: 'online',
    });
  });

  it('keeps avatar spacing around the contact name', () => {
    createWrapper();

    const contactText = wrapper
      .get('[data-testid="conversation-header-contact-name"]')
      .element.closest('.ml-2');

    expect(contactText).not.toBeNull();
  });

  it('opens contact details when the closed panel header area is clicked', async () => {
    createWrapper();

    await wrapper
      .get('[data-testid="conversation-header-contact"]')
      .trigger('click');

    expectContactSidebarToOpen(1);
  });

  it('closes contact details when the open panel header area is clicked again', async () => {
    createWrapper();
    const contactHeaderArea = wrapper.get(
      '[data-testid="conversation-header-contact"]'
    );

    await contactHeaderArea.trigger('click');
    await contactHeaderArea.trigger('click');

    expectContactSidebarToOpen(1);
    expectContactSidebarToClose(2);
  });

  it('toggles contact details when contact header children are clicked', async () => {
    createWrapper();

    await wrapper
      .get('[data-testid="conversation-header-contact-name"]')
      .trigger('click');
    await wrapper
      .get('[data-testid="conversation-header-conversation-id"]')
      .trigger('click');
    await wrapper.get('[data-testid="contact-avatar"]').trigger('click');

    expect(updateUISettings).toHaveBeenCalledTimes(3);
    expectContactSidebarToOpen(1);
    expectContactSidebarToClose(2);
    expectContactSidebarToOpen(3);
  });

  it('toggles contact details from the main contact header area with Enter', async () => {
    createWrapper();
    const contactHeaderArea = wrapper.get(
      '[data-testid="conversation-header-contact"]'
    );

    await contactHeaderArea.trigger('keydown.enter');
    await contactHeaderArea.trigger('keydown.enter');

    expectContactSidebarToOpen(1);
    expectContactSidebarToClose(2);
  });

  it('toggles contact details from the main contact header area with Space', async () => {
    createWrapper();
    const contactHeaderArea = wrapper.get(
      '[data-testid="conversation-header-contact"]'
    );

    await contactHeaderArea.trigger('keydown.space');
    await contactHeaderArea.trigger('keydown.space');

    expectContactSidebarToOpen(1);
    expectContactSidebarToClose(2);
  });

  it('does not toggle contact details when the resolve action is clicked', async () => {
    createWrapper();

    await wrapper.get('[data-testid="resolve-action-button"]').trigger('click');

    expect(resolveButtonClick).toHaveBeenCalled();
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('does not toggle contact details when the actions menu is clicked', async () => {
    createWrapper();

    await wrapper.get('[data-testid="more-actions-button"]').trigger('click');

    expect(menuButtonClick).toHaveBeenCalled();
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('keeps the remaining header actions available without opening contact details', async () => {
    createWrapper();

    await wrapper
      .get('[data-testid="conversation-call-button"]')
      .trigger('click');

    expect(callButtonClick).toHaveBeenCalled();
    expect(updateUISettings).not.toHaveBeenCalled();
  });
});
