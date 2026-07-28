import {
  currentEmbeddedDepth,
  goBackEmbedded,
  pushEmbedded,
} from '../embeddedConversationHistory';

describe('embeddedConversationHistory', () => {
  const backRoute = { name: 'kanban_board_show' };

  afterEach(() => {
    window.history.replaceState({}, '');
  });

  it('pushes an embedded conversation with its depth', () => {
    const router = { push: vi.fn() };

    pushEmbedded(router, { path: '/conversation/2' }, 2);

    expect(router.push).toHaveBeenCalledWith({
      path: '/conversation/2',
      state: { embeddedDepth: 2 },
    });
  });

  it('returns one history entry when the embedded depth is greater than zero', () => {
    const router = { go: vi.fn(), push: vi.fn() };
    window.history.replaceState({ embeddedDepth: 2 }, '');

    expect(currentEmbeddedDepth()).toBe(2);
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
