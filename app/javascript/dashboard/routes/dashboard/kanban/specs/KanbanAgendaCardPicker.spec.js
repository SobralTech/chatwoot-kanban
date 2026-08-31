import { flushPromises, mount } from '@vue/test-utils';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import KanbanAgendaCardPicker from '../agenda/KanbanAgendaCardPicker.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/api/kanbanBoards', () => ({
  default: { getBoardCards: vi.fn() },
}));

const responsePage = (cards, nextCursor = null) => ({
  data: {
    cards,
    pagination: { next_cursor: nextCursor },
  },
});

describe('KanbanAgendaCardPicker', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('searches every page of open cards by subject or contact', async () => {
    KanbanBoardsAPI.getBoardCards
      .mockResolvedValueOnce(
        responsePage(
          [
            {
              id: 11,
              subject: 'Renewal',
              due_at: '2026-08-20T12:00:00Z',
              contact: { name: 'Jane' },
            },
          ],
          { after_id: 11 }
        )
      )
      .mockResolvedValueOnce(
        responsePage([
          { id: 12, subject: 'Upgrade', contact: { name: 'Jane Cooper' } },
        ])
      );

    const wrapper = mount(KanbanAgendaCardPicker, {
      props: { boardId: 3 },
      global: { stubs: { NextButton: true } },
    });

    await wrapper
      .find('[data-testid="kanban-agenda-card-search"]')
      .setValue('Jane');
    await vi.advanceTimersByTimeAsync(300);
    await flushPromises();

    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenNthCalledWith(1, 3, {
      q: 'Jane',
      card_statuses: ['open'],
      limit: 50,
      cursor: undefined,
    });
    expect(KanbanBoardsAPI.getBoardCards).toHaveBeenNthCalledWith(2, 3, {
      q: 'Jane',
      card_statuses: ['open'],
      limit: 50,
      cursor: { after_id: 11 },
    });
    expect(wrapper.findAll('[data-card-id]')).toHaveLength(2);

    await wrapper.find('[data-card-id="11"]').trigger('click');
    expect(wrapper.emitted('scheduled')[0][0]).toMatchObject({
      id: 11,
      dueAt: '2026-08-20T12:00:00Z',
    });
  });
});
