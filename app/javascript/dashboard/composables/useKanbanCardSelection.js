import { computed, ref } from 'vue';

// Shift-click extends the range within a single stage, so the anchor tracks the stage
// it was set in and a shift-click anywhere else falls back to a plain toggle.
export function useKanbanCardSelection({
  findCardStage,
  selectionLimit,
  t,
  useAlert,
}) {
  const selectedCardIds = ref(new Set());
  const selectionAnchor = ref(null);

  const isSelectionMode = computed(() => selectedCardIds.value.size > 0);

  const clearCardSelection = () => {
    selectedCardIds.value = new Set();
    selectionAnchor.value = null;
  };

  const exceedsLimit = size => {
    const limit = selectionLimit.value;
    if (!limit || size <= limit) return false;

    useAlert(t('KANBAN.BULK.LIMIT', { count: limit }));
    return true;
  };

  const rangeToAnchor = (stage, card) => {
    const anchor = selectionAnchor.value;
    if (!anchor || anchor.stageId !== stage.id) return null;

    const anchorIndex = stage.cards.findIndex(item => item.id === anchor.id);
    const cardIndex = stage.cards.findIndex(item => item.id === card.id);
    if (anchorIndex < 0 || cardIndex < 0) return null;

    const start = Math.min(anchorIndex, cardIndex);
    const end = Math.max(anchorIndex, cardIndex);
    return stage.cards.slice(start, end + 1);
  };

  const toggleCardSelection = (card, event = {}) => {
    const stage = findCardStage(card);
    if (!stage) return;

    const nextSelectedCardIds = new Set(selectedCardIds.value);
    const isSelected = nextSelectedCardIds.has(card.id);
    const rangeCards = event.shiftKey ? rangeToAnchor(stage, card) : null;

    if (rangeCards) {
      const addedCount = rangeCards.filter(
        item => !nextSelectedCardIds.has(item.id)
      ).length;
      if (exceedsLimit(nextSelectedCardIds.size + addedCount)) return;

      rangeCards.forEach(item => nextSelectedCardIds.add(item.id));
    } else if (isSelected) {
      nextSelectedCardIds.delete(card.id);
    } else {
      if (exceedsLimit(nextSelectedCardIds.size + 1)) return;

      nextSelectedCardIds.add(card.id);
    }

    selectionAnchor.value = { id: card.id, stageId: stage.id };
    selectedCardIds.value = nextSelectedCardIds;
  };

  return {
    clearCardSelection,
    isSelectionMode,
    selectedCardIds,
    toggleCardSelection,
  };
}
