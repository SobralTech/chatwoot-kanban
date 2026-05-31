import { mount, flushPromises } from '@vue/test-utils';
import KanbanOpportunityPicker from '../KanbanOpportunityPicker.vue';
import ContactAPI from 'dashboard/api/contacts';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';

const storeMock = vi.hoisted(() => ({
  inboxesById: {},
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/api/contacts', () => ({
  default: {
    search: vi.fn(),
    getConversations: vi.fn(),
    getContactableInboxes: vi.fn(),
  },
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: {
    createManualCard: vi.fn(),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInboxById': inboxId => storeMock.inboxesById[inboxId] || {},
    },
  }),
}));

const mountPicker = () =>
  mount(KanbanOpportunityPicker, {
    props: {
      kanbanBoardId: 10,
      kanbanStageId: 100,
    },
  });

const buildContact = overrides => ({
  id: 1,
  name: 'Jane Cooper',
  email: 'jane@example.com',
  phone_number: '+155501',
  thumbnail: null,
  ...overrides,
});

const buildInbox = overrides => ({
  source_id: 'src-1',
  inbox: {
    id: 10,
    name: 'Email Inbox',
    channel_type: 'Channel::Email',
    avatar_url: null,
    channel_id: 20,
    provider: null,
  },
  ...overrides,
});

const buildConversation = overrides => ({
  id: 1000,
  inboxId: 10,
  meta: {
    channel: 'Channel::Email',
  },
  ...overrides,
});

const searchAndSelectContact = async (wrapper, query, contactIndex = 0) => {
  const input = wrapper.find('[data-testid="kanban-contact-search-input"]');
  await input.setValue(query);
  await vi.advanceTimersByTimeAsync(300);
  await flushPromises();
  const buttons = wrapper.findAll(
    '[data-testid="kanban-contact-search-results"] button'
  );
  await buttons[contactIndex].trigger('click');
  await flushPromises();
};

const searchAndSelectFirstContact = async (wrapper, query) =>
  searchAndSelectContact(wrapper, query, 0);

const searchAndSelectFirstInbox = async wrapper => {
  await searchAndSelectFirstContact(wrapper, 'Jan');

  const inboxButtons = wrapper.findAll('[data-testid="kanban-inboxes"] button');
  await inboxButtons[0].trigger('click');
};

const subjectInput = wrapper =>
  wrapper.find('[data-testid="kanban-manual-card-subject"]');

describe('KanbanOpportunityPicker', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
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
    ContactAPI.getConversations.mockResolvedValue({ data: { payload: [] } });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders search input', () => {
    const wrapper = mountPicker();
    expect(
      wrapper.find('[data-testid="kanban-contact-search-input"]').exists()
    ).toBe(true);
  });

  it('does not search for queries shorter than 3 characters', async () => {
    vi.useFakeTimers();
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('');
    await input.setValue('J');
    await input.setValue('Ja');
    await vi.advanceTimersByTimeAsync(350);

    expect(ContactAPI.search).not.toHaveBeenCalled();
  });

  it('performs debounced search for 3+ character query', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    expect(ContactAPI.search).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(ContactAPI.search).toHaveBeenCalledWith('Jan', 1, 'name', '', {
      signal: expect.any(AbortSignal),
    });
  });

  it('aborts stale request when query changes', async () => {
    vi.useFakeTimers();
    const signals = [];
    ContactAPI.search.mockImplementation((...args) => {
      signals.push(args[4].signal);
      return new Promise(() => {});
    });
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    expect(signals[0].aborted).toBe(false);

    await input.setValue('Jane');
    expect(signals[0].aborted).toBe(true);
  });

  it('shows loading state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockReturnValue(new Promise(() => {}));
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);

    expect(
      wrapper.find('[data-testid="kanban-contact-search-loading"]').exists()
    ).toBe(true);
  });

  it('shows empty state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-contact-search-empty"]').text()
    ).toContain('KANBAN.ADD_ITEM.NO_CONTACTS');
  });

  it('shows error state', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockRejectedValue(new Error('Search failed'));
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="kanban-contact-search-error"]').text()
    ).toContain('KANBAN.ADD_ITEM.SEARCH_ERROR');
  });

  it('selects a contact result', async () => {
    vi.useFakeTimers();
    ContactAPI.search.mockResolvedValue({
      data: { payload: [buildContact()] },
    });
    ContactAPI.getConversations.mockResolvedValue({
      data: { payload: [buildConversation()] },
    });
    ContactAPI.getContactableInboxes.mockResolvedValue({
      data: { payload: [buildInbox()] },
    });
    const wrapper = mountPicker();

    await searchAndSelectFirstContact(wrapper, 'Jan');

    const selected = wrapper.find('[data-testid="kanban-selected-contact"]');
    expect(selected.text()).toContain('Jane Cooper');
  });

  it('emits close on close button click', async () => {
    const wrapper = mountPicker();
    await wrapper.find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]').trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('aborts pending request on unmount', async () => {
    vi.useFakeTimers();
    const signals = [];
    ContactAPI.search.mockImplementation((...args) => {
      signals.push(args[4].signal);
      return new Promise(() => {});
    });
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    expect(signals[0].aborted).toBe(false);

    wrapper.unmount();
    expect(signals[0].aborted).toBe(true);
  });

  describe('contact inboxes', () => {
    beforeEach(() => {
      ContactAPI.search.mockResolvedValue({
        data: { payload: [buildContact()] },
      });
    });

    it('loads conversations after selecting a contact', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(ContactAPI.getConversations).toHaveBeenCalledWith(1, {
        signal: expect.any(AbortSignal),
      });
    });

    it('derives unique inboxes from conversation inbox ids', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation(),
            buildConversation({ id: 1001 }),
            buildConversation({
              id: 1002,
              inboxId: 11,
              meta: {
                channel: 'Channel::Whatsapp',
              },
            }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      const inboxButtons = wrapper.findAll(
        '[data-testid="kanban-inboxes"] button'
      );
      const inboxes = wrapper.find('[data-testid="kanban-inboxes"]');
      expect(inboxButtons).toHaveLength(2);
      expect(inboxes.text()).toContain('Email Inbox');
      expect(inboxes.text()).toContain('Email');
      expect(inboxes.text()).toContain('WhatsApp Inbox');
      expect(inboxes.text()).toContain('Whatsapp');
    });

    it('falls back to inbox id and conversation channel without store data', async () => {
      vi.useFakeTimers();
      storeMock.inboxesById = {};
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation({
              id: 10,
              inboxId: 3,
              meta: {
                channel: 'Channel::Whatsapp',
              },
            }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      const inboxes = wrapper.find('[data-testid="kanban-inboxes"]');
      expect(inboxes.text()).toContain('Inbox #3');
      expect(inboxes.text()).toContain('Whatsapp');
      expect(ContactAPI.getContactableInboxes).not.toHaveBeenCalled();
    });

    it('does not call fallback when conversations provide inboxes', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(ContactAPI.getContactableInboxes).not.toHaveBeenCalled();
    });

    it('calls fallback when conversations have no inboxes', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation({ inboxId: null })] },
      });
      ContactAPI.getContactableInboxes.mockResolvedValue({
        data: { payload: [buildInbox()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(ContactAPI.getContactableInboxes).toHaveBeenCalledWith(1, {
        signal: expect.any(AbortSignal),
      });
      expect(wrapper.find('[data-testid="kanban-inboxes"]').text()).toContain(
        'Email Inbox'
      );
    });

    it('calls fallback when conversations fail', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockRejectedValue(new Error('Failed'));
      ContactAPI.getContactableInboxes.mockResolvedValue({
        data: { payload: [buildInbox()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(ContactAPI.getContactableInboxes).toHaveBeenCalledWith(1, {
        signal: expect.any(AbortSignal),
      });
      expect(wrapper.find('[data-testid="kanban-inboxes"]').text()).toContain(
        'Email Inbox'
      );
    });

    it('shows loading state while fetching inboxes', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockReturnValue(new Promise(() => {}));
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(
        wrapper.find('[data-testid="kanban-inboxes-loading"]').exists()
      ).toBe(true);
    });

    it('renders inbox results with name and channel type', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation(),
            buildConversation({
              id: 1001,
              inboxId: 11,
              meta: {
                channel: 'Channel::Whatsapp',
              },
            }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      const inboxes = wrapper.find('[data-testid="kanban-inboxes"]');
      expect(inboxes.text()).toContain('Email Inbox');
      expect(inboxes.text()).toContain('Email');
      expect(inboxes.text()).toContain('WhatsApp Inbox');
      expect(inboxes.text()).toContain('Whatsapp');
    });

    it('allows selecting an inbox', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation(),
            buildConversation({
              id: 1001,
              inboxId: 11,
              meta: {
                channel: 'Channel::Sms',
              },
            }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      const inboxButtons = wrapper.findAll(
        '[data-testid="kanban-inboxes"] button'
      );
      await inboxButtons[1].trigger('click');

      expect(inboxButtons[0].classes()).not.toContain('bg-n-alpha-2');
      expect(inboxButtons[1].classes()).toContain('bg-n-alpha-2');
    });

    it('renders subject input after selecting an inbox', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);

      expect(
        wrapper.find('[data-testid="kanban-manual-card-subject"]').exists()
      ).toBe(true);
    });

    it('generates a default subject after selecting an inbox', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);

      expect(subjectInput(wrapper).element.value).toBe(
        'Jane Cooper - Email Inbox'
      );
    });

    it('submits the generated subject unchanged', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockResolvedValue({ data: {} });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
        card: {
          kanban_stage_id: 100,
          contact_id: 1,
          inbox_id: 10,
          subject: 'Jane Cooper - Email Inbox',
        },
      });
    });

    it('allows replacing the generated subject', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockResolvedValue({ data: {} });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await subjectInput(wrapper).setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
        card: {
          kanban_stage_id: 100,
          contact_id: 1,
          inbox_id: 10,
          subject: 'Notebook quote',
        },
      });
    });

    it('updates the generated subject when inbox changes while untouched', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation(),
            buildConversation({ id: 1001, inboxId: 11 }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      const inboxButtons = wrapper.findAll(
        '[data-testid="kanban-inboxes"] button'
      );
      await inboxButtons[1].trigger('click');

      expect(subjectInput(wrapper).element.value).toBe(
        'Jane Cooper - WhatsApp Inbox'
      );
    });

    it('preserves customized subject when inbox changes', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: {
          payload: [
            buildConversation(),
            buildConversation({ id: 1001, inboxId: 11 }),
          ],
        },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await subjectInput(wrapper).setValue('Custom opportunity');
      const inboxButtons = wrapper.findAll(
        '[data-testid="kanban-inboxes"] button'
      );
      await inboxButtons[1].trigger('click');

      expect(subjectInput(wrapper).element.value).toBe('Custom opportunity');
    });

    it('resets subject when clearing the selected contact', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await subjectInput(wrapper).setValue('Custom opportunity');
      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLEAR_CONTACT"]')
        .trigger('click');
      await searchAndSelectFirstInbox(wrapper);

      expect(subjectInput(wrapper).element.value).toBe(
        'Jane Cooper - Email Inbox'
      );
    });

    it('resets subject when selecting another contact', async () => {
      vi.useFakeTimers();
      ContactAPI.search
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 1, name: 'Alice' })] },
        })
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 2, name: 'Bob' })] },
        });
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectContact(wrapper, 'Ali');
      await wrapper
        .findAll('[data-testid="kanban-inboxes"] button')[0]
        .trigger('click');
      await subjectInput(wrapper).setValue('Custom opportunity');
      await searchAndSelectContact(wrapper, 'Bob');
      await wrapper
        .findAll('[data-testid="kanban-inboxes"] button')[0]
        .trigger('click');

      expect(subjectInput(wrapper).element.value).toBe('Bob - Email Inbox');
    });

    it('resets subject when picker closes', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      ContactAPI.search.mockResolvedValue({
        data: { payload: [buildContact()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await subjectInput(wrapper).setValue('Custom opportunity');
      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]')
        .trigger('click');
      await searchAndSelectFirstInbox(wrapper);

      expect(subjectInput(wrapper).element.value).toBe(
        'Jane Cooper - Email Inbox'
      );
    });

    it('does not submit a blank subject', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('   ');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).not.toHaveBeenCalled();
      expect(
        wrapper.find('[data-testid="kanban-manual-card-subject-error"]').text()
      ).toContain('KANBAN.ADD_ITEM.SUBJECT_REQUIRED');
    });

    it('sends the trimmed subject when creating a manual card', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockResolvedValue({ data: {} });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('  Cotação de notebooks  ');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
        card: {
          kanban_stage_id: 100,
          contact_id: 1,
          inbox_id: 10,
          subject: 'Cotação de notebooks',
        },
      });
    });

    it('submits manual cards with board, stage, contact, inbox, and subject', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockResolvedValue({ data: {} });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledWith(10, {
        card: {
          kanban_stage_id: 100,
          contact_id: 1,
          inbox_id: 10,
          subject: 'Notebook quote',
        },
      });
    });

    it('disables submit while saving', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockReturnValue(new Promise(() => {}));
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      const submit = wrapper.find('[data-testid="kanban-manual-card-submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
      expect(submit.text()).toContain('KANBAN.ADD_ITEM.SAVING');
    });

    it('prevents duplicate submits while saving', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockReturnValue(new Promise(() => {}));
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');

      expect(KanbanBoardsAPI.createManualCard).toHaveBeenCalledTimes(1);
    });

    it('renders API errors', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({
        data: { payload: [buildConversation()] },
      });
      KanbanBoardsAPI.createManualCard.mockRejectedValue({
        response: { data: { message: 'Subject already exists' } },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');
      await flushPromises();

      expect(
        wrapper.find('[data-testid="kanban-manual-card-error"]').text()
      ).toContain('Subject already exists');
    });

    it('emits created and close on success', async () => {
      vi.useFakeTimers();
      ContactAPI.getContactableInboxes.mockResolvedValue({
        data: { payload: [buildInbox()] },
      });
      KanbanBoardsAPI.createManualCard.mockResolvedValue({ data: {} });
      const wrapper = mountPicker();

      await searchAndSelectFirstInbox(wrapper);
      await wrapper
        .find('[data-testid="kanban-manual-card-subject"]')
        .setValue('Notebook quote');
      await wrapper
        .find('[data-testid="kanban-manual-card-form"]')
        .trigger('submit');
      await flushPromises();

      expect(wrapper.emitted('created')).toBeTruthy();
      expect(wrapper.emitted('close')).toBeTruthy();
      expect(
        wrapper.find('[data-testid="kanban-manual-card-form"]').exists()
      ).toBe(false);
    });

    it('shows empty state when no inboxes are available', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockResolvedValue({ data: { payload: [] } });
      ContactAPI.getContactableInboxes.mockResolvedValue({
        data: { payload: [] },
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(
        wrapper.find('[data-testid="kanban-inboxes-empty"]').exists()
      ).toBe(true);
      expect(
        wrapper.find('[data-testid="kanban-inboxes-empty"]').text()
      ).toContain('KANBAN.ADD_ITEM.NO_INBOXES');
    });

    it('shows error state when inbox fetch fails', async () => {
      vi.useFakeTimers();
      ContactAPI.getConversations.mockRejectedValue(
        new Error('Conversation fetch failed')
      );
      ContactAPI.getContactableInboxes.mockRejectedValue(
        new Error('Inbox fetch failed')
      );
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(
        wrapper.find('[data-testid="kanban-inboxes-error"]').exists()
      ).toBe(true);
      expect(
        wrapper.find('[data-testid="kanban-inboxes-error"]').text()
      ).toContain('KANBAN.ADD_ITEM.INBOXES_ERROR');
    });

    it('resets inbox state when clearing the selected contact', async () => {
      vi.useFakeTimers();
      const conversationSignals = [];
      ContactAPI.getConversations.mockImplementation((...args) => {
        conversationSignals.push(args[1].signal);
        return new Promise(() => {});
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');

      expect(conversationSignals[0].aborted).toBe(false);

      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLEAR_CONTACT"]')
        .trigger('click');

      expect(conversationSignals[0].aborted).toBe(true);
      expect(
        wrapper.find('[data-testid="kanban-inboxes-loading"]').exists()
      ).toBe(false);
    });

    it('resets inbox state when selecting another contact', async () => {
      vi.useFakeTimers();
      const conversationSignals = [];
      ContactAPI.getConversations.mockImplementation((...args) => {
        conversationSignals.push(args[1].signal);
        return new Promise(() => {});
      });
      ContactAPI.search
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 1, name: 'Alice' })] },
        })
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 2, name: 'Bob' })] },
        });

      const wrapper = mountPicker();

      // Select Alice
      await searchAndSelectFirstContact(wrapper, 'Ali');
      expect(conversationSignals[0].aborted).toBe(false);

      // Clear Alice
      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLEAR_CONTACT"]')
        .trigger('click');

      // Select Bob
      await searchAndSelectFirstContact(wrapper, 'Bob');

      expect(conversationSignals[0].aborted).toBe(true);
      expect(conversationSignals[1].aborted).toBe(false);
    });

    it('resets inbox state when picker closes', async () => {
      vi.useFakeTimers();
      const conversationSignals = [];
      ContactAPI.getConversations.mockImplementation((...args) => {
        conversationSignals.push(args[1].signal);
        return new Promise(() => {});
      });
      const wrapper = mountPicker();

      await searchAndSelectFirstContact(wrapper, 'Jan');
      expect(conversationSignals[0].aborted).toBe(false);

      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLOSE"]')
        .trigger('click');

      expect(conversationSignals[0].aborted).toBe(true);
      expect(wrapper.emitted('close')).toBeTruthy();
    });

    it('aborts stale inbox request when contact changes before resolution', async () => {
      vi.useFakeTimers();
      const conversationSignals = [];
      ContactAPI.getConversations.mockImplementation((...args) => {
        conversationSignals.push(args[1].signal);
        return new Promise(() => {});
      });
      ContactAPI.search
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 1, name: 'Alice' })] },
        })
        .mockResolvedValueOnce({
          data: { payload: [buildContact({ id: 2, name: 'Bob' })] },
        });

      const wrapper = mountPicker();

      // Start loading inboxes for Alice
      await searchAndSelectFirstContact(wrapper, 'Ali');
      expect(conversationSignals[0].aborted).toBe(false);

      // Clear Alice
      await wrapper
        .find('[aria-label="KANBAN.ADD_ITEM.CLEAR_CONTACT"]')
        .trigger('click');

      // Select Bob while Alice's request is still pending
      await searchAndSelectFirstContact(wrapper, 'Bob');

      // Alice's request should be aborted, Bob's should be active
      expect(conversationSignals[0].aborted).toBe(true);
      expect(conversationSignals[1].aborted).toBe(false);
    });

    it('renders with no-drag class for Draggable compatibility', () => {
      const wrapper = mountPicker();
      expect(wrapper.classes()).toContain('no-drag');
    });
  });
});
