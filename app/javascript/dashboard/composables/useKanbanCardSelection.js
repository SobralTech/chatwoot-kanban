import { computed, ref } from 'vue';

// A plain click opens a selection gesture and fixes its direction; shift-clicks paint
// the range from the anchor in that same direction, so the anchor stays put until the
// next plain click. A shift-click outside the anchor's stage falls back to a plain toggle.
export function useKanbanCardSelection({
  findCardStage,
  selectionLimit,
  stages,
  t,
  useAlert,
}) {
  const selectedCardIds = ref(new Set());
  const selectionAnchor = ref(null);

  const isSelectionMode = computed(() => selectedCardIds.value.size > 0);

  const selectedCards = computed(() =>
    stages.value.flatMap(stage =>
      stage.cards.filter(card => selectedCardIds.value.has(card.id))
    )
  );

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
    const rangeCards = event.shiftKey ? rangeToAnchor(stage, card) : null;
    const targetCards = rangeCards ?? [card];
    const isSelecting = rangeCards
      ? selectionAnchor.value.isSelecting
      : !nextSelectedCardIds.has(card.id);

    if (isSelecting) {
      const addedCards = targetCards.filter(
        item => !nextSelectedCardIds.has(item.id)
      );
      if (exceedsLimit(nextSelectedCardIds.size + addedCards.length)) return;

      addedCards.forEach(item => nextSelectedCardIds.add(item.id));
    } else {
      targetCards.forEach(item => nextSelectedCardIds.delete(item.id));
    }

    if (!rangeCards) {
      selectionAnchor.value = { id: card.id, stageId: stage.id, isSelecting };
    }
    selectedCardIds.value = nextSelectedCardIds;
  };

  return {
    clearCardSelection,
    isSelectionMode,
    selectedCardIds,
    selectedCards,
    toggleCardSelection,
  };
}
