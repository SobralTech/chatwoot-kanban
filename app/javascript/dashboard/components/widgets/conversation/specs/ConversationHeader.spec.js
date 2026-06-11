import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { ref } from 'vue';

import ConversationHeader from '../ConversationHeader.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

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

vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));

describe('ConversationHeader', () => {
  let chat;
  let contact;
  let inbox;
  let store;
  let updateUISettings;
  let wrapper;

  const createWrapper = () => {
    updateUISettings = vi.fn();

    store = createStore({
      getters: {
        getSelectedChat: () => chat,
        getCurrentAccountId: () => 1,
        getUISettings: () => ({
          is_contact_sidebar_open: false,
          is_copilot_panel_open: true,
        }),
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
          ConversationCallButton: {
            name: 'ConversationCallButton',
            template: '<button data-testid="conversation-call-button" />',
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
            template: '<button data-testid="more-actions-button" />',
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

  const expectContactSidebarToOpen = () => {
    expect(updateUISettings).toHaveBeenCalledWith(expect.any(Object), {
      uiSettings: {
        is_contact_sidebar_open: true,
        is_copilot_panel_open: false,
      },
    });
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
    copyTextToClipboard.mockResolvedValue();
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  it('does not render the contact avatar in the conversation header', () => {
    createWrapper();

    expect(wrapper.findComponent({ name: 'Avatar' }).exists()).toBe(false);
    expect(wrapper.html()).not.toContain('avatar.png');
  });

  it('does not keep avatar spacing around the contact name', () => {
    createWrapper();

    const contactArea = wrapper.get(
      '[data-testid="conversation-header-contact"]'
    );

    expect(contactArea.classes()).not.toContain('ml-2');
    expect(contactArea.classes()).not.toContain('rtl:mr-2');
  });

  it('opens contact details when the contact name is clicked', async () => {
    createWrapper();

    await wrapper
      .get('[data-testid="conversation-header-contact-name"]')
      .trigger('click');

    expectContactSidebarToOpen();
  });

  it('opens contact details from the contact name with Enter and Space', async () => {
    createWrapper();
    const contactNameButton = wrapper.get(
      '[data-testid="conversation-header-contact-name"]'
    );

    await contactNameButton.trigger('keydown.enter');
    await contactNameButton.trigger('keydown.space');

    expect(updateUISettings).toHaveBeenCalledTimes(2);
    expectContactSidebarToOpen();
  });

  it('keeps the remaining header actions available', async () => {
    createWrapper();

    expect(
      wrapper.get('[data-testid="conversation-call-button"]').exists()
    ).toBe(true);
    expect(wrapper.get('[data-testid="more-actions-button"]').exists()).toBe(
      true
    );

    await wrapper
      .get('[data-testid="conversation-header-conversation-id"]')
      .trigger('click');

    expect(copyTextToClipboard).toHaveBeenCalledWith('42');
  });
});
