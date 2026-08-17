import { onUnmounted } from 'vue';

export const FLUSH_DELAY = 500;

const createBuffer = () => ({
  board: false,
  stageIds: new Set(),
  cardIds: new Set(),
  cardStageIds: new Set(),
});

const addAll = (target, ids) =>
  ids.filter(Boolean).forEach(id => target.add(id));

export function useKanbanRealtimeBuffer({ onFlush }) {
  let timer = null;
  let buffer = createBuffer();

  const flush = () => {
    timer = null;
    const pending = buffer;
    buffer = createBuffer();

    if (!pending.board && !pending.stageIds.size && !pending.cardIds.size) {
      return;
    }

    onFlush({
      board: pending.board,
      stageIds: [...pending.stageIds],
      cardIds: [...pending.cardIds],
      cardStageIds: [...pending.cardStageIds],
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
    addAll(buffer.stageIds, stageIds);
    addAll(buffer.cardIds, cardIds);
    addAll(buffer.cardStageIds, cardStageIds);
    schedule();
  };

  onUnmounted(() => {
    clearTimeout(timer);
    timer = null;
    buffer = createBuffer();
  });

  return { push };
}
