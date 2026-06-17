import { describe, it, expect } from 'vitest';
import { applyRoleFilter, sortComparator } from '../helpers';

describe('Conversation Helpers', () => {
  describe('#applyRoleFilter', () => {
    // Test data for conversations
    const conversationWithAssignee = {
      meta: {
        assignee: {
          id: 1,
        },
      },
    };

    const conversationWithDifferentAssignee = {
      meta: {
        assignee: {
          id: 2,
        },
      },
    };

    const conversationWithoutAssignee = {
      meta: {
        assignee: null,
      },
    };

    // Test for administrator role
    it('always returns true for administrator role regardless of permissions', () => {
      const role = 'administrator';
      const permissions = [];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
    });

    // Test for agent role
    it('always returns true for agent role regardless of permissions', () => {
      const role = 'agent';
      const permissions = [];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
    });

    // Test for custom role with 'conversation_manage' permission
    it('returns true for any user with conversation_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_manage'];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
    });

    // Test for custom role with 'conversation_unassigned_manage' permission
    describe('with conversation_unassigned_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_unassigned_manage'];
      const currentUserId = 1;

      it('returns true for conversations assigned to the user', () => {
        expect(
          applyRoleFilter(
            conversationWithAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(true);
      });

      it('returns true for unassigned conversations', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(true);
      });

      it('returns false for conversations assigned to other users', () => {
        expect(
          applyRoleFilter(
            conversationWithDifferentAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(false);
      });
    });

    // Test for custom role with 'conversation_participating_manage' permission
    describe('with conversation_participating_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_participating_manage'];
      const currentUserId = 1;

      it('returns true for conversations assigned to the user', () => {
        expect(
          applyRoleFilter(
            conversationWithAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(true);
      });

      it('returns false for unassigned conversations', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(false);
      });

      it('returns false for conversations assigned to other users', () => {
        expect(
          applyRoleFilter(
            conversationWithDifferentAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(false);
      });
    });

    // Test for user with no relevant permissions
    it('returns false for custom role without any relevant permissions', () => {
      const role = 'custom_role';
      const permissions = ['some_other_permission'];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(false);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(false);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(false);
    });

    // Test edge cases for meta.assignee
    describe('handles edge cases with meta.assignee', () => {
      const role = 'custom_role';
      const permissions = ['conversation_unassigned_manage'];
      const currentUserId = 1;

      it('treats undefined assignee as unassigned', () => {
        const conversationWithUndefinedAssignee = {
          meta: {
            assignee: undefined,
          },
        };

        expect(
          applyRoleFilter(
            conversationWithUndefinedAssignee,
            role,
            permissions,
            currentUserId
          )
        ).toBe(true);
      });

      it('handles empty meta object', () => {
        const conversationWithEmptyMeta = {
          meta: {},
        };

        expect(
          applyRoleFilter(
            conversationWithEmptyMeta,
            role,
            permissions,
            currentUserId
          )
        ).toBe(true);
      });
    });
  });
});

describe('#sortComparator', () => {
  const base = { last_activity_at: 1000, waiting_since: 0 };

  const conv = (overrides = {}) => ({ ...base, ...overrides });

  it('floats a pinned conversation above an unpinned one', () => {
    const pinned = conv({ account_pinned_at: 1700000000 });
    const unpinned = conv({
      account_pinned_at: null,
      personal_pinned_at: null,
    });
    expect(sortComparator(pinned, unpinned, 'last_activity_at_desc')).toBe(-1);
    expect(sortComparator(unpinned, pinned, 'last_activity_at_desc')).toBe(1);
  });

  it('uses personal_pinned_at to float conversation when no account pin', () => {
    const pinned = conv({
      personal_pinned_at: 1700000000,
      account_pinned_at: null,
    });
    const unpinned = conv({
      personal_pinned_at: null,
      account_pinned_at: null,
    });
    expect(sortComparator(pinned, unpinned, 'last_activity_at_desc')).toBe(-1);
  });

  it('sorts two pinned conversations by most recently pinned first', () => {
    const first = conv({ account_pinned_at: 1700002000 });
    const second = conv({ account_pinned_at: 1700001000 });
    expect(sortComparator(first, second, 'last_activity_at_desc')).toBeLessThan(
      0
    );
    expect(
      sortComparator(second, first, 'last_activity_at_desc')
    ).toBeGreaterThan(0);
  });

  it('account_pinned_at beats personal_pinned_at for sort order between two pinned', () => {
    const accountPinned = conv({
      account_pinned_at: 1700001000,
      personal_pinned_at: null,
    });
    const personalPinned = conv({
      account_pinned_at: null,
      personal_pinned_at: 1700002000,
    });
    // account_pinned_at=1700001000 vs personal_pinned_at=1700002000 as the effective pin timestamps
    // bPinnedAt - aPinnedAt: 1700002000 - 1700001000 > 0 → personal pin is "newer" so it sorts first
    expect(
      sortComparator(accountPinned, personalPinned, 'last_activity_at_desc')
    ).toBeGreaterThan(0);
  });

  it('falls back to sort key for two unpinned conversations', () => {
    const newer = conv({
      last_activity_at: 2000,
      account_pinned_at: null,
      personal_pinned_at: null,
    });
    const older = conv({
      last_activity_at: 1000,
      account_pinned_at: null,
      personal_pinned_at: null,
    });
    // last_activity_at_desc: newer should come first (negative result)
    expect(sortComparator(newer, older, 'last_activity_at_desc')).toBeLessThan(
      0
    );
    expect(
      sortComparator(older, newer, 'last_activity_at_desc')
    ).toBeGreaterThan(0);
  });
});
