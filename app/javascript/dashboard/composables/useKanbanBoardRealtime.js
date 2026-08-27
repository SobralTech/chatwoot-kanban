import { onMounted, onUnmounted, ref } from 'vue';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useKanbanRealtimeBuffer } from './useKanbanRealtimeBuffer';

// A stage, card or board change anywhere else in the account reaches the board
// as one of these. Everything that changes the board's own shape costs a full
// reload; the rest is answered with the smallest refresh that covers it.
const BOARD_REFRESH_EVENTS = new Set([
  'kanban.board.updated',
  'kanban.stage.created',
  'kanban.stage.updated',
  'kanban.stage.deleted',
  'kanban.stage.reordered',
]);

// Beyond this many buffered cards, refreshing whole stages costs less than
// fetching each card on its own.
const MAX_INDIVIDUAL_CARDS = 5;

/**
 * Keeps an open board in step with what other people are doing to it. Events
 * are buffered so a burst becomes one refresh, and held back entirely while a
 * card is being dragged, which the caller reports through `isCardDragging` and
 * releases through the returned flush.
 */
export function useKanbanBoardRealtime({
  findCardStageId,
  hasActiveFilters,
  isCardDragging,
  normalizePayload,
  patchVisibleCard,
  refreshSelectedBoard,
  refreshStageFirstPage,
  refreshStageFirstPages,
  requestGeneration,
  selectedBoard,
}) {
  const pendingEvents = ref([]);
  // A move made here comes back over the websocket like anyone else's. The drop already
  // applied it locally, so refreshing both columns would redraw the very same cards; the
  // echo is dropped, and only for the card this client just moved. The window only has to
  // outlast the broadcast, which rides a background job and took seconds to arrive in
  // development - someone else moving the very same card inside it loses nothing but the
  // ordering, until the next event on that board.
  const SELF_ECHO_TTL = 20000;
  const selfMovedCardExpiries = new Map();

  const suppressCardReorderEcho = cardId => {
    if (!cardId) return;

    selfMovedCardExpiries.set(cardId, Date.now() + SELF_ECHO_TTL);
  };

  const isSelfCardReorderEcho = cardId => {
    const expiresAt = selfMovedCardExpiries.get(cardId);
    if (!expiresAt) return false;

    selfMovedCardExpiries.delete(cardId);
    return expiresAt > Date.now();
  };

  // The board may have moved on while the request was in flight; anything it
  // answers about the old one is discarded rather than patched in.
  const isStale = (generation, boardId) =>
    generation !== requestGeneration.value ||
    selectedBoard.value?.id !== boardId;

  const patchCardById = async cardId => {
    const generation = requestGeneration.value;
    const boardId = selectedBoard.value?.id;
    if (!boardId) return;
    const localStageId = findCardStageId({ id: cardId });

    try {
      const response = await KanbanBoardsAPI.showCardById(boardId, cardId);
      if (isStale(generation, boardId)) return;

      const card = normalizePayload(response.data);
      const updatedStageId = findCardStageId(card);

      if (card.active === false || !patchVisibleCard(card)) {
        await refreshStageFirstPages([localStageId, updatedStageId]);
      }
    } catch {
      if (isStale(generation, boardId)) return;

      await refreshStageFirstPage(localStageId);
    }
  };

  const applyFlush = async ({ board, stageIds, cardIds, cardStageIds }) => {
    if (!selectedBoard.value?.id) return;
    if (board) {
      await refreshSelectedBoard();
      return;
    }

    if (cardIds.length > MAX_INDIVIDUAL_CARDS) {
      await refreshStageFirstPages([
        ...stageIds,
        ...cardStageIds,
        ...cardIds.map(cardId => findCardStageId({ id: cardId })),
      ]);
      return;
    }

    if (stageIds.length) await refreshStageFirstPages(stageIds);
    await Promise.all(cardIds.map(patchCardById));
  };

  const buffer = useKanbanRealtimeBuffer({ onFlush: applyFlush });

  const bufferEvent = (event, data) => {
    if (BOARD_REFRESH_EVENTS.has(event)) {
      buffer.push({ board: true });
      return;
    }

    if (event === 'kanban.card.created' || event === 'kanban.card.deleted') {
      buffer.push({ stageIds: [data.stage_id] });
      return;
    }

    if (event === 'kanban.card.reordered') {
      if (isSelfCardReorderEcho(data.card_id)) return;

      buffer.push({
        stageIds: [data.source_stage_id, data.target_stage_id],
      });
      return;
    }

    if (event === 'kanban.card.updated') {
      // Under filters a card can leave the visible set entirely, so the stages
      // it came from and went to both have to be refetched.
      if (hasActiveFilters.value) {
        buffer.push({
          stageIds: [data.stage_id, findCardStageId({ id: data.card_id })],
        });
        return;
      }

      buffer.push({
        cardIds: [data.card_id],
        cardStageIds: [data.stage_id],
      });
    }
  };

  const isForOpenBoard = data =>
    !!selectedBoard.value?.id && data?.board_id === selectedBoard.value.id;

  const flushPendingEvents = () => {
    if (!pendingEvents.value.length) return;

    const events = pendingEvents.value;
    pendingEvents.value = [];

    events.forEach(({ event, data }) => {
      if (isForOpenBoard(data)) bufferEvent(event, data);
    });
  };

  const handleEvent = ({ event, data } = {}) => {
    if (!isForOpenBoard(data)) return;

    // Applying a refresh mid-drag would pull the card out from under the
    // pointer, so the event waits for the drop.
    if (isCardDragging.value) {
      pendingEvents.value.push({ event, data });
      return;
    }

    bufferEvent(event, data);
  };

  onMounted(() => emitter.on(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleEvent));
  onUnmounted(() => emitter.off(BUS_EVENTS.KANBAN_REALTIME_EVENT, handleEvent));

  return { flushPendingEvents, suppressCardReorderEcho };
}
