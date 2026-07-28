import { shallowMount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';

import ContactConversations from '../ContactConversations.vue';
import { EMBEDDED_CONVERSATION } from 'dashboard/composables/useEmbeddedConversation';

const mocks = vi.hoisted(() => ({
  push: vi.fn(),
  dispatch: vi.fn(),
  route: {
    name: 'kanban_board_conversation',
    params: {
      accountId: '1',
      boardId: '10',
    },
  },
}));

vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ push: mocks.push }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: mocks.dispatch }),
  useMapGetter: key => {
    const getters = {
      getSelectedChat: ref({ id: 1 }),
      'contactConversations/getUIFlags': ref({ isFetching: false }),
      'contacts/getContact': ref(() => ({})),
      'inboxes/getInbox': ref(() => ({})),
      getSelectedInbox: ref(null),
      'inboxes/getInboxes': ref([]),
      'contactConversations/getContactConversation': ref(() => [
        {
          id: 2,
          inbox_id: 3,
          meta: { sender: { id: 7 } },
          labels: [],
        },
      ]),
    };

    return getters[key];
  },
}));

vi.mock('dashboard/store/modules/conversations/helpers/actionHelpers', () => ({
  isOnMentionsView: () => false,
  isOnUnattendedView: () => false,
  isOnFoldersView: () => false,
}));

const mountConversations = () =>
  shallowMount(ContactConversations, {
    props: {
      contactId: 7,
      conversationId: 1,
    },
    global: {
      provide: {
        [EMBEDDED_CONVERSATION]: ref({
          backRoute: { name: 'kanban_board_show' },
        }),
      },
      stubs: {
        ConversationCard: {
          name: 'ConversationCard',
          template: '<button data-testid="conversation-card" />',
        },
        ContextMenu: true,
        ConversationContextMenu: true,
        Spinner: true,
      },
    },
  });

describe('ContactConversations embedded navigation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('keeps contact history navigation in kanban mode and marks the origin', async () => {
    const wrapper = mountConversations();

    wrapper.getComponent({ name: 'ConversationCard' }).vm.$emit('click', {});
    await nextTick();

    expect(mocks.push).toHaveBeenCalledWith({
      path: '/app/accounts/1/kanban/10/conversations/2',
      state: { fromEmbedded: true },
    });
  });
});
