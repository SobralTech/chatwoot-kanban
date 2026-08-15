import { onUnmounted } from 'vue';

const FLUSH_DELAY = 500;
const MAX_INDIVIDUAL_CARDS = 5;

export function useKanbanRealtimeBuffer({ onFlush }) {
  let timer = null;
  let buffer = {
    board: false,
    stageIds: new Set(),
    cardIds: new Set(),
    cardStageIds: new Set(),
  };

  const reset = () => {
    buffer = {
      board: false,
      stageIds: new Set(),
      cardIds: new Set(),
      cardStageIds: new Set(),
    };
  };

  const flush = () => {
    timer = null;
    const pending = buffer;
    reset();
    if (!pending.board && !pending.stageIds.size && !pending.cardIds.size)
      return;
    const hasTooManyCards = pending.cardIds.size > MAX_INDIVIDUAL_CARDS;
    onFlush({
      board: pending.board,
      stageIds: [
        ...new Set([
          ...pending.stageIds,
          ...(hasTooManyCards ? pending.cardStageIds : []),
        ]),
      ],
      cardIds: hasTooManyCards ? [] : [...pending.cardIds],
    });
  };

  const schedule = () => {
    if (timer) return;
    timer = setTimeout(flush, FLUSH_DELAY);
  };

  const push = ({
    board = false,
    stageIds = [],
    cardIds = [],
    cardStageIds = [],
  }) => {
    if (board) buffer.board = true;
    stageIds.filter(Boolean).forEach(id => buffer.stageIds.add(id));
    cardIds.filter(Boolean).forEach(id => buffer.cardIds.add(id));
    cardStageIds.filter(Boolean).forEach(id => buffer.cardStageIds.add(id));
    schedule();
  };

  const cancel = () => {
    clearTimeout(timer);
    timer = null;
    reset();
  };
  onUnmounted(cancel);

  return { push, flush, cancel };
}
