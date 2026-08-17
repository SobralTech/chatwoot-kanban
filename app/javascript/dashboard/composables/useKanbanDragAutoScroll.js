import { ref } from 'vue';

export function useKanbanDragAutoScroll(boardScrollContainer) {
  // Auto-scroll while dragging. SortableJS runs in fallback mode (see the card
  // and stage Draggable options), so the pointer keeps emitting events during a
  // drag and we can drive both axes ourselves: the board scrolls horizontally
  // and the column under the pointer scrolls vertically.
  const AUTO_SCROLL_EDGE = 120;
  const AUTO_SCROLL_MAX_SPEED = 24;
  let dragPointerX = -1;
  let dragPointerY = -1;
  let dragPointerReady = false;
  let autoScrollRaf = null;
  const isDraggingBoard = ref(false);

  const onDragPointerMove = event => {
    dragPointerX = event.clientX;
    dragPointerY = event.clientY;
    dragPointerReady = true;
  };

  // Ramps from 0 at the edge threshold up to AUTO_SCROLL_MAX_SPEED at the very
  // border, so the board eases in instead of jumping at a fixed speed.
  const edgeScrollDelta = (position, start, end) => {
    if (position < start + AUTO_SCROLL_EDGE) {
      const intensity =
        (start + AUTO_SCROLL_EDGE - position) / AUTO_SCROLL_EDGE;
      return -AUTO_SCROLL_MAX_SPEED * Math.min(intensity, 1);
    }
    if (position > end - AUTO_SCROLL_EDGE) {
      const intensity =
        (position - (end - AUTO_SCROLL_EDGE)) / AUTO_SCROLL_EDGE;
      return AUTO_SCROLL_MAX_SPEED * Math.min(intensity, 1);
    }
    return 0;
  };

  const runBoardAutoScroll = () => {
    const board = boardScrollContainer.value;
    if (board && dragPointerReady) {
      const boardRect = board.getBoundingClientRect();
      const dx = edgeScrollDelta(dragPointerX, boardRect.left, boardRect.right);
      if (dx) {
        board.scrollLeft = Math.max(
          0,
          Math.min(board.scrollLeft + dx, board.scrollWidth - board.clientWidth)
        );
      }

      // Sortable's fallback clone is pointer-events: none, so this resolves to
      // the column actually under the cursor.
      const column = document
        .elementFromPoint(dragPointerX, dragPointerY)
        ?.closest('[data-stage-scroll-id]');
      if (column) {
        const columnRect = column.getBoundingClientRect();
        const dy = edgeScrollDelta(
          dragPointerY,
          columnRect.top,
          columnRect.bottom
        );
        if (dy) {
          column.scrollTop = Math.max(
            0,
            Math.min(
              column.scrollTop + dy,
              column.scrollHeight - column.clientHeight
            )
          );
        }
      }
    }
    autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
  };

  const startBoardAutoScroll = () => {
    if (autoScrollRaf) return;
    isDraggingBoard.value = true;
    dragPointerReady = false;
    dragPointerX = -1;
    dragPointerY = -1;
    document.addEventListener('pointermove', onDragPointerMove);
    autoScrollRaf = requestAnimationFrame(runBoardAutoScroll);
  };

  const stopBoardAutoScroll = () => {
    document.removeEventListener('pointermove', onDragPointerMove);
    if (autoScrollRaf) cancelAnimationFrame(autoScrollRaf);
    autoScrollRaf = null;
    dragPointerReady = false;
    isDraggingBoard.value = false;
  };

  // vuedraggable forwards unknown attributes straight to SortableJS as options,
  // so these have to be real booleans: written as bare attributes they resolve to
  // "" and silently leave the native HTML5 drag backend in place, which emits no
  // pointer events and therefore no auto-scroll. Sortable's own scroll plugin is
  // off because runBoardAutoScroll drives both axes.
  const sortableFallbackOptions = {
    forceFallback: true,
    fallbackOnBody: true,
    scroll: false,
  };

  return {
    isDraggingBoard,
    sortableFallbackOptions,
    startBoardAutoScroll,
    stopBoardAutoScroll,
  };
}
