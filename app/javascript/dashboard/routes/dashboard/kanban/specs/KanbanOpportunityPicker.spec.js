import { flushPromises, mount } from '@vue/test-utils';
import KanbanOpportunityPicker from '../KanbanOpportunityPicker.vue';
import ContactAPI from 'dashboard/api/contacts';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const storeMock = vi.hoisted(() => ({
  inboxesById: {},
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => {
      if (key === 'KANBAN.ADD_ITEM.TITLE_WITH_STAGE') {
        return `New card in «${values.stageName}»`;
      }

      return values?.query ? `${key}:${values.query}` : key;
    },
  }),
}));

vi.mock('dashboard/api/contacts', () => ({
  default: {
    get: vi.fn(),
    search: vi.fn(),
    getConversations: vi.fn(),
    getContactableInboxes: vi.fn(),
  },
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    createManualCard: vi.fn(),
    lookupCards: vi.fn(),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInboxById': inboxId => storeMock.inboxesById[inboxId] || {},
    },
  }),
}));

const buildContact = overrides => ({
  id: 1,
  name: 'Jane Cooper',
  email: 'jane@example.com',
  phone_number: '+155501',
  thumbnail: null,
  ...overrides,
});

const buildConversation = overrides => ({
  id: 1000,
  inbox_id: 10,
  meta: {
    channel: 'Channel::Email',
  },
  status: 'open',
  timestamp: 1_700_000_000,
  last_activity_at: 1_700_000_000,
  messages: [{ content: 'I need help with my order.' }],
  ...overrides,
});

const buildInbox = overrides => ({
  source_id: 'src-1',
  inbox: {
    id: 10,
    name: 'Email Inbox',
    channel_type: 'Channel::Email',
    avatar_url: null,
  },
  ...overrides,
});

const mountPicker = (props = {}) =>
  mount(KanbanOpportunityPicker, {
    props: {
      kanbanBoardId: 10,
      kanbanStageId: 100,
      kanbanStageName: 'Prospecting',
      inboxScopeMode: 'selected_inboxes',
      allowedInboxIds: [10],
      ...props,
    },
    global: {
      stubs: {
        Avatar: true,
        ChannelIcon: true,
      },
    },
  });

const setUpContactSearch = () => {
  ContactAPI.search.mockResolvedValue({
    data: { payload: [buildContact()] },
  });
};

const searchAndSelectContact = async wrapper => {
  const input = wrapper.find(
    'input[data-testid="kanban-contact-search-input"]'
  );
  await input.setValue('Ja');
  await vi.advanceTimersByTimeAsync(300);
  await flushPromises();
  await wrapper
    .find('[data-testid="kanban-contact-search-results"] button')
    .trigger('click');
  await flushPromises();
};

const selectConversation = async wrapper => {
  await wrapper
    .find('[data-testid="kanban-conversation-list"] button')
    .trigger('click');
  await flushPromises();
};

describe('KanbanOpportunityPicker', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    storeMock.inboxesById = {
      10: {
        id: 10,
        name: 'Email Inbox',
        channelType: 'Channel::Email',
      },
      11: {
        id: 11,
        name: 'WhatsApp Inbox',
        channelType: 'Channel::Whatsapp',
      },
    };
    ContactAPI.get.mockResolvedValue({ data: { payload: [buildContact()] } });
    ContactAPI.getConversations.mockResolvedValue({
      data: { payload: [buildConversation()] },
    });
    ContactAPI.getContactableInboxes.mockResolvedValue({
      data: { payload: [buildInbox()] },
    });
    KanbanBoardsAPI.lookupCards.mockResolvedValue({ data: [] });
    KanbanBoardsAPI.createManualCard.mockResolvedValue({
      data: { id: 500, kanban_stage_id: 100 },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('lists recent contacts when opened', async () => {
    const wrapper = mountPicker();
    await flushPromises();

    expect(ContactAPI.get).toHaveBeenCalledWith(1, 'last_activity_at');
    expect(
      wrapper.find('[data-testid="kanban-contact-search-results"]').text()
    ).toContain('Jane Cooper');
  });

  it('renders the stage name without decorative quotation marks', () => {
    const wrapper = mountPicker();

    expect(wrapper.find('[data-testid="kanban-add-item-title"]').text()).toBe(
      'New card in Prospecting'
    );
  });

  it('searches from two characters with debounce and aborts stale requests', async () => {
    const signals = [];
    ContactAPI.search.mockImplementation((...args) => {
      signals.push(args[4].signal);
      return new Promise(() => {});
    });
    const wrapper = mountPicker();
    const input = wrapper.find(
      'input[data-testid="kanban-contact-search-input"]'
    );

    await input.setValue('J');
    await vi.advanceTimersByTimeAsync(350);
    expect(ContactAPI.search).not.toHaveBeenCalled();

    await input.setValue('Ja');
    await vi.advanceTimersByTimeAsync(300);
    expect(ContactAPI.search).toHaveBeenCalledWith('Ja', 1, 'name', '', {
      signal: expect.any(AbortSignal),
    });
    expect(signals[0].aborted).toBe(false);

    await input.setValue('Jan');
    expect(signals[0].aborted).toBe(true);
  });

  it('filters conversations outside the board inbox scope', async () => {
    setUpContactSearch();
    ContactAPI.getConversations.mockResolvedValue({
      data: {
        payload: [
          buildConversation(),
          buildConversation({ id: 1001, inbox_id: 11 }),
        ],
      },
    });
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);

    const conversations = wrapper.findAll(
      '[data-testid="kanban-conversation-list"] button'
    );
    expect(conversations).toHaveLength(1);
    expect(conversations[0].text()).toContain('Email Inbox');
    expect(ContactAPI.getContactableInboxes).not.toHaveBeenCalled();
  });

  it('shows the selected contact, inbox, and last message timestamp', async () => {
    setUpContactSearch();
    ContactAPI.getConversations.mockResolvedValue({
      data: {
        payload: [
          buildConversation({
            messages: [
              {
                content: 'I need help with my order.',
                created_at: 1_700_000_100,
              },
            ],
          }),
        ],
      },
    });
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);
    await selectConversation(wrapper);

    expect(
      wrapper.find('[data-testid="kanban-card-selection-summary"]').text()
    ).toContain('Jane Cooper');
    expect(
      wrapper
        .find('[data-testid="kanban-card-selection-inbox"]')
        .attributes('title')
    ).toBe('Email Inbox');
    expect(
      wrapper
        .find('[data-testid="kanban-card-selection-last-message-at"]')
        .text()
    ).toMatch(/\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}/);
    expect(
      wrapper.find('[data-testid="kanban-card-selection-last-message"]').text()
    ).toContain('I need help with my order.');
  });

  it.each([
    ['audio', 'ogg', 'i-lucide-audio-lines', 'OGG'],
    ['video', 'mp4', 'i-lucide-video', 'MP4'],
    ['file', 'pdf', 'i-lucide-paperclip', 'PDF'],
  ])(
    'shows the last %s attachment when the conversation messages are empty',
    async (fileType, extension, iconClass, preview) => {
      setUpContactSearch();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation({
              messages: [],
              last_non_activity_message: {
                created_at: 1_700_000_100,
                message_type: 1,
                attachments: [{ file_type: fileType, extension }],
              },
            }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectContact(wrapper);
      await selectConversation(wrapper);

      expect(wrapper.find(`.${iconClass}`).exists()).toBe(true);
      expect(wrapper.find('.i-lucide-check-check').exists()).toBe(true);
      expect(
        wrapper
          .find('[data-testid="kanban-card-selection-last-message"]')
          .text()
      ).toContain(preview);
    }
  );

  it('marks an eligible conversation that already has a card', async () => {
    setUpContactSearch();
    KanbanBoardsAPI.lookupCards.mockResolvedValue({
      data: [
        {
          id: 22,
          subject: 'Existing card',
          kanban_stage_id: 100,
          stage_name: 'Prospecting',
          conversation_id: 1000,
          terminal: false,
        },
      ],
    });
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);

    expect(
      wrapper.find('[data-testid="kanban-conversation-has-card"]').text()
    ).toContain('KANBAN.ADD_ITEM.HAS_CARD_BADGE');
  });

  it('falls back to allowed contactable inboxes without an eligible conversation', async () => {
    setUpContactSearch();
    ContactAPI.getConversations.mockResolvedValue({
      data: { payload: [buildConversation({ inbox_id: 11 })] },
    });
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);

    expect(ContactAPI.getContactableInboxes).toHaveBeenCalledWith(1, {
      signal: expect.any(AbortSignal),
    });
    const fallback = wrapper.find('[data-testid="kanban-fallback-inboxes"]');
    expect(fallback.text()).toContain(
      'KANBAN.ADD_ITEM.NO_ELIGIBLE_CONVERSATIONS'
    );

    await fallback.find('button').trigger('click');
    expect(wrapper.find('[data-testid="kanban-card-step"]').exists()).toBe(
      true
    );
  });

  it('requires three subject characters and submits the selected conversation display id', async () => {
    setUpContactSearch();
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);
    await selectConversation(wrapper);

    const subject = wrapper.find('[data-testid="kanban-manual-card-subject"]');
    const submit = wrapper.find('[data-testid="kanban-manual-card-submit"]');
    expect(submit.attributes('disabled')).toBeDefined();

    await subject.setValue('ab');
    expect(submit.attributes('disabled')).toBeDefined();

    await subject.setValue('New card');
    expect(submit.attributes('disabled')).toBeUndefined();
    await wrapper
      .find('[data-testid="kanban-manual-card-form"]')
      .trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
      card: {
        kanban_stage_id: 100,
        contact_id: 1,
        subject: 'New card',
        conversation_display_id: 1000,
      },
    });
    expect(wrapper.emitted('created')[0][0]).toMatchObject({
      id: 500,
      kanbanStageId: 100,
    });
  });

  it('includes the prefilled due date when creating from the agenda', async () => {
    setUpContactSearch();
    const wrapper = mountPicker({
      initialDueAt: '2026-09-02T03:00:00.000Z',
    });

    await searchAndSelectContact(wrapper);
    await selectConversation(wrapper);
    await wrapper
      .find('[data-testid="kanban-manual-card-subject"]')
      .setValue('Scheduled card');
    await wrapper
      .find('[data-testid="kanban-manual-card-form"]')
      .trigger('submit');
    await flushPromises();

    expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
      card: expect.objectContaining({
        subject: 'Scheduled card',
        due_at: '2026-09-02T03:00:00.000Z',
      }),
    });
  });

  it('renders duplicate subject errors beside the subject field', async () => {
    setUpContactSearch();
    KanbanBoardsAPI.createManualCard.mockRejectedValue({
      response: {
        data: {
          error:
            'Manual opportunity with this subject already exists for this contact and inbox',
        },
      },
    });
    const wrapper = mountPicker();

    await searchAndSelectContact(wrapper);
    await selectConversation(wrapper);
    await wrapper
      .find('[data-testid="kanban-manual-card-subject"]')
      .setValue('Existing card');
    await wrapper
      .find('[data-testid="kanban-manual-card-form"]')
      .trigger('submit');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-manual-card-subject-error"]').text()
    ).toContain('KANBAN.ADD_ITEM.ERRORS.DUPLICATE_SUBJECT');
  });
});
