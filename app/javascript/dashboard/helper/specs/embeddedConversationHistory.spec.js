import { goBackEmbedded, pushEmbedded } from '../embeddedConversationHistory';

describe('embeddedConversationHistory', () => {
  const backRoute = { name: 'kanban_board_show' };

  afterEach(() => {
    window.history.replaceState({}, '');
  });

  it('marks a conversation pushed from another embedded conversation', () => {
    const router = { push: vi.fn() };

    pushEmbedded(router, { path: '/conversation/2' }, true);

    expect(router.push).toHaveBeenCalledWith({
      path: '/conversation/2',
      state: { fromEmbedded: true },
    });
  });

  it('defaults to not coming from an embedded conversation', () => {
    const router = { push: vi.fn() };

    pushEmbedded(router, { path: '/conversation/2' });

    expect(router.push).toHaveBeenCalledWith({
      path: '/conversation/2',
      state: { fromEmbedded: false },
    });
  });

  it('returns one history entry when arriving from an embedded conversation', () => {
    const router = { go: vi.fn(), push: vi.fn() };
    window.history.replaceState({ fromEmbedded: true }, '');

    goBackEmbedded(router, backRoute);

    expect(router.go).toHaveBeenCalledWith(-1);
    expect(router.push).not.toHaveBeenCalled();
  });

  it('navigates to the fallback route when there is no embedded history', () => {
    const router = { go: vi.fn(), push: vi.fn() };

    goBackEmbedded(router, backRoute);

    expect(router.push).toHaveBeenCalledWith(backRoute);
    expect(router.go).not.toHaveBeenCalled();
  });
});
