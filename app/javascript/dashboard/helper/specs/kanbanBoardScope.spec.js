import { boardAcceptsInbox } from 'dashboard/helper/kanbanBoardScope';

describe('boardAcceptsInbox', () => {
  it('accepts any inbox for an open funnel', () => {
    expect(boardAcceptsInbox({ inbox_scope_mode: 'all_inboxes' }, 42)).toBe(
      true
    );
  });

  it('accepts a listed inbox for a selected-inboxes funnel', () => {
    expect(
      boardAcceptsInbox(
        { inbox_scope_mode: 'selected_inboxes', allowed_inboxes: [{ id: 42 }] },
        42
      )
    ).toBe(true);
  });

  it('rejects an unlisted inbox for a selected-inboxes funnel', () => {
    expect(
      boardAcceptsInbox(
        { inboxScopeMode: 'selected_inboxes', allowedInboxIds: [7] },
        42
      )
    ).toBe(false);
  });
});
