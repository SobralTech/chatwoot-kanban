import { computed, ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { normalize, normalizeCard } from 'dashboard/helper/kanbanPayload';
import { toIso8601 } from 'dashboard/helper/kanbanDueDate';

// subject, priority, dueAt and description are one key each on the card details
// endpoint, so they only differ by wire name, serialization and error message.
const DETAIL_FIELDS = {
  subject: {
    payloadKey: 'subject',
    serialize: value => value,
    errorKey: 'KANBAN.OPPORTUNITY_DETAILS.SUBJECT_UPDATE_ERROR',
  },
  priority: {
    payloadKey: 'priority',
    serialize: value => value || null,
    errorKey: 'KANBAN.CARD.PRIORITY_UPDATE_ERROR',
  },
  dueAt: {
    payloadKey: 'due_at',
    serialize: toIso8601,
    errorKey: 'KANBAN.CARD.DUE_DATE_UPDATE_ERROR',
  },
  description: {
    payloadKey: 'description',
    serialize: value => value.trim() || null,
    errorKey: 'KANBAN.OPPORTUNITY_DETAILS.DESCRIPTION_UPDATE_ERROR',
  },
};

/**
 * Persists one opportunity field at a time, optimistically. Shared by the
 * opportunity panel and the conversation sidebar list so both surfaces write a
 * field the same way; the caller only says where the card lives, how to patch
 * it, and how to turn ids into the objects a card carries.
 */
export function useKanbanCardFields({
  t,
  boardIdFor,
  patchCard,
  onUpdated = () => {},
  onAssignableUsers = () => {},
  resolveLabels = titles => titles.map(title => ({ title })),
  resolveAssignees = ids => ids.map(id => ({ id })),
}) {
  const pendingKeys = ref(new Set());

  const keyFor = (card, field) => `${card?.id}:${field}`;
  const isPending = (card, field) => pendingKeys.value.has(keyFor(card, field));
  const isCardPending = card =>
    [...pendingKeys.value].some(key => key.startsWith(`${card?.id}:`));
  const hasPendingUpdates = computed(() => pendingKeys.value.size > 0);

  const setPending = (card, field, pending) => {
    const next = new Set(pendingKeys.value);
    next[pending ? 'add' : 'delete'](keyFor(card, field));
    pendingKeys.value = next;
  };

  const run = async (card, field, { optimistic, request, apply, errorKey }) => {
    const boardId = boardIdFor(card);
    if (!boardId || isPending(card, field)) return false;

    // Only the keys this update touches need rolling back.
    const previousValues = Object.fromEntries(
      Object.keys(optimistic).map(key => [key, card[key]])
    );

    setPending(card, field, true);
    patchCard(card, optimistic);

    try {
      const response = await request(boardId);
      // A request that resolves to false has already reported its own failure.
      if (response === false) {
        patchCard(card, previousValues);
        return false;
      }

      patchCard(card, apply(response));
      onUpdated(card);
      return true;
    } catch (error) {
      patchCard(card, previousValues);
      // The endpoints answer with a reason often enough to be worth showing.
      useAlert(
        typeof errorKey === 'function'
          ? errorKey(error)
          : apiErrorMessage(error, t(errorKey))
      );
      return false;
    } finally {
      setPending(card, field, false);
    }
  };

  // `patchKey` is for surfaces that hold the value under a different name than
  // the details endpoint uses: the board's compact card spends `priority` on the
  // conversation's priority and keeps the card's own under `cardPriority`.
  const updateDetail = (card, field, value, { patchKey = field } = {}) => {
    const { payloadKey, serialize, errorKey } = DETAIL_FIELDS[field];

    return run(card, field, {
      optimistic: { [patchKey]: value },
      request: boardId =>
        KanbanBoardsAPI.updateCardDetailsById(boardId, card.id, {
          [payloadKey]: serialize(value),
        }),
      apply: response => {
        const saved = normalizeCard(response)[field];
        return { [patchKey]: saved === undefined ? value : saved };
      },
      errorKey,
    });
  };

  const updateLabels = (card, titles) =>
    run(card, 'labels', {
      optimistic: { labels: resolveLabels(titles, card) },
      request: boardId =>
        KanbanBoardsAPI.updateCardLabels(boardId, card.id, titles),
      apply: response => {
        const saved = normalize(
          response?.data?.payload ?? response?.data ?? []
        );
        return {
          labels: Array.isArray(saved) ? saved : resolveLabels(titles, card),
        };
      },
      errorKey: 'KANBAN.CARD.LABELS_UPDATE_ERROR',
    });

  const updateAssignees = (card, ids) =>
    run(card, 'assignees', {
      optimistic: { assignees: resolveAssignees(ids, card) },
      request: boardId =>
        KanbanBoardsAPI.updateCardAssignees(boardId, card.id, ids),
      apply: response => {
        const payload = normalize(response?.data || {});
        if (payload.assignableUsers) {
          onAssignableUsers(card, payload.assignableUsers);
        }

        return { assignees: payload.payload || resolveAssignees(ids, card) };
      },
      errorKey: 'KANBAN.CARD.ASSIGN_ERROR',
    });

  return {
    isPending,
    isCardPending,
    hasPendingUpdates,
    run,
    updateDetail,
    updateLabels,
    updateAssignees,
  };
}
