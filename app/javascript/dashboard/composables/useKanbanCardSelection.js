import { computed, ref } from 'vue';

// Shift-click toggles the range within a single stage, so the anchor tracks the stage
// it was set in and a shift-click anywhere else falls back to a plain toggle.
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

    if (nextSelectedCardIds.has(card.id)) {
      targetCards.forEach(item => nextSelectedCardIds.delete(item.id));
    } else {
      const addedCards = targetCards.filter(
        item => !nextSelectedCardIds.has(item.id)
      );
      if (exceedsLimit(nextSelectedCardIds.size + addedCards.length)) return;

      addedCards.forEach(item => nextSelectedCardIds.add(item.id));
    }

    selectionAnchor.value = { id: card.id, stageId: stage.id };
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
