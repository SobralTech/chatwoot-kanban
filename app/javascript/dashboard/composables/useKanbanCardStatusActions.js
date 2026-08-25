import { computed, toValue } from 'vue';

import { reasonsOfType } from 'dashboard/helper/kanbanCardStatus';

// Won/lost/reopen is offered from four surfaces: the board card menu, the
// sidebar card menu, the sidebar quick-close buttons and the status badge.
// They all need the same answers — does this board close cards at all, is this
// card still open, can the reason step be skipped, and what does the change
// payload look like — so the answers live here instead of once per surface.
export function useKanbanCardStatusActions({
  stageId,
  wonStageId,
  lostStageId,
  reasons,
  lostReasonRequired,
}) {
  const wonId = computed(() => Number(toValue(wonStageId)) || null);
  const lostId = computed(() => Number(toValue(lostStageId)) || null);
  const currentStageId = computed(() => Number(toValue(stageId)) || null);

  const hasTerminals = computed(() => !!wonId.value && !!lostId.value);

  // A board without terminal stages has no card to call won or lost, so the
  // null ids must never match a card that is missing its stage id.
  const status = computed(() => {
    if (!hasTerminals.value) return 'open';
    if (currentStageId.value === wonId.value) return 'won';
    if (currentStageId.value === lostId.value) return 'lost';
    return 'open';
  });
  const isOpen = computed(() => status.value === 'open');

  // Asking for a reason when there is none to pick is an empty dialog: close in
  // one step instead of drilling into a sub-view.
  const canSkipReason = type =>
    type !== 'reopen' &&
    !reasonsOfType(toValue(reasons), type).length &&
    !(type === 'lost' && toValue(lostReasonRequired));

  const statusPayloadFor = (type, reasonId = null) =>
    type === 'reopen'
      ? { reopen: true }
      : {
          targetStageId: type === 'won' ? wonId.value : lostId.value,
          reasonId: reasonId || null,
        };

  return { hasTerminals, status, isOpen, canSkipReason, statusPayloadFor };
}
