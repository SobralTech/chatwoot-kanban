import { shallowMount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import ContactPanel from '../ContactPanel.vue';
import KanbanConversationCards from '../Kanban/KanbanConversationCards.vue';

const dispatchMock = vi.fn();
const isContactSidebarItemOpenMock = vi.fn(() => true);
const toggleSidebarUIStateMock = vi.fn();
const conversationSidebarItemsOrderMock = ref([
  { name: 'conversation_actions' },
  { name: 'macros' },
  { name: 'kanban' },
  { name: 'conversation_info' },
]);

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    updateUISettings: vi.fn(),
    isContactSidebarItemOpen: isContactSidebarItemOpenMock,
    conversationSidebarItemsOrder: conversationSidebarItemsOrderMock,
    toggleSidebarUIState: toggleSidebarUIStateMock,
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: dispatchMock,
  }),
  useMapGetter: key => {
    const getters = {
      getSelectedChat: ref({
        id: 456,
        inbox_id: 12,
        meta: {
          channel: 'Channel::Email',
          sender: { id: 7 },
        },
      }),
      'conversationMetadata/getConversationMetadata': ref(() => ({
        additional_attributes: {},
      })),
      'contacts/getContact': ref(() => ({
        id: 7,
        additional_attributes: {},
      })),
    };

    return getters[key] || ref({});
  },
  useFunctionGetter: () =>
    ref({
      enabled: false,
      id: null,
    }),
}));

const DraggableStub = {
  props: ['list'],
  template: `
    <div>
      <div v-for="element in list" :key="element.name">
        <slot name="item" :element="element" />
      </div>
    </div>
  `,
};

const AccordionItemStub = {
  props: ['title'],
  template: `
    <section>
      <h3>{{ title }}</h3>
      <slot />
    </section>
  `,
};

const mountPanel = () =>
  shallowMount(ContactPanel, {
    props: {
      conversationId: 456,
      inboxId: 12,
    },
    global: {
      mocks: {
        $t: key => {
          const translations = {
            'CONVERSATION_SIDEBAR.ACCORDION.KANBAN': 'Kanban',
            'CONVERSATION_SIDEBAR.ACCORDION.MACROS': 'Macros',
            'CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS':
              'Conversation Actions',
            'CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO':
              'Conversation Information',
            'CONVERSATION.SIDEBAR.CONTACT': 'Contact',
          };

          return translations[key] || key;
        },
      },
      stubs: {
        Draggable: DraggableStub,
        AccordionItem: AccordionItemStub,
        ContactInfo: true,
        SidebarActionsHeader: true,
        ConversationAction: true,
        MacrosList: true,
        ConversationInfo: true,
        KanbanConversationCards,
        'woot-feature-toggle': {
          template: '<div><slot /></div>',
        },
      },
    },
  });

describe('ContactPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders Kanban accordion in the conversation sidebar', async () => {
    const wrapper = mountPanel();
    await nextTick();

    expect(wrapper.text()).toContain('Kanban');
    expect(wrapper.findComponent(KanbanConversationCards).exists()).toBe(true);
    expect(wrapper.findComponent(KanbanConversationCards).props()).toEqual({
      conversationId: 456,
    });
  });

  it('keeps Kanban after macros and before conversation info', async () => {
    const wrapper = mountPanel();
    await nextTick();
    const text = wrapper.text();

    expect(text.indexOf('Macros')).toBeLessThan(text.indexOf('Kanban'));
    expect(text.indexOf('Kanban')).toBeLessThan(
      text.indexOf('Conversation Information')
    );
  });
});
