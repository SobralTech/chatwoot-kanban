import { mount, flushPromises } from '@vue/test-utils';
import KanbanOpportunityPicker from '../KanbanOpportunityPicker.vue';
import ContactAPI from 'dashboard/api/contacts';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/api/contacts', () => ({
  default: {
    search: vi.fn(),
  },
}));

const mountPicker = () =>
  mount(KanbanOpportunityPicker, {
    props: {
      kanbanStageId: 100,
    },
  });

describe('KanbanOpportunityPicker', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
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
      data: {
        payload: [
          {
            id: 1,
            name: 'Jane Cooper',
            email: 'jane@example.com',
            phone_number: '+155501',
          },
        ],
      },
    });
    const wrapper = mountPicker();
    const input = wrapper.find('[data-testid="kanban-contact-search-input"]');

    await input.setValue('Jan');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();
    await wrapper
      .find('[data-testid="kanban-contact-search-results"] button')
      .trigger('click');

    const selected = wrapper.find('[data-testid="kanban-selected-contact"]');
    expect(selected.text()).toContain('Jane Cooper');
    expect(selected.text()).toContain(
      'KANBAN.ADD_ITEM.CONVERSATIONS_NEXT_STEP'
    );
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
});
