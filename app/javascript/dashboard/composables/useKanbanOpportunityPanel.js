import { nextTick, ref, watch } from 'vue';

import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { pushEmbedded } from 'dashboard/helper/embeddedConversationHistory';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

/**
 * Which opportunity the board has open, and every way in and out of it: the
 * card that opens it, the deep link that opens it, and the four places it can
 * send the user afterwards. The board itself only renders the panel.
 */
export function useKanbanOpportunityPanel({
  findCardStageId,
  hasActiveFilters,
  openRemoveCardConfirmation,
  patchVisibleCard,
  refreshSelectedBoard,
  refreshStageFirstPage,
  refreshStageFirstPages,
  route,
  router,
  saveBoardSnapshot,
  selectedBoard,
  suppressNextCardClick,
  t,
}) {
  const selectedOpportunityCardId = ref(null);
  // Where focus goes when the panel closes: the card that opened it.
  const triggerElement = ref(null);

  const boardIdForCard = card =>
    Number(card?.kanbanBoardId ?? selectedBoard.value?.id);

  const navigateToConversationInNewTab = card => {
    // A standalone tab opens the conversation on its own inbox route rather
    // than the board-embedded one. The board stays mounted in this tab and the
    // new tab gets its own sessionStorage, so there is no snapshot to save.
    const path = frontendURL(
      conversationUrl({
        accountId: route.params.accountId,
        id: card.conversationId,
      })
    );
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener,noreferrer'
    );
  };

  const navigateToConversation = card => {
    saveBoardSnapshot();
    pushEmbedded(router, {
      name: 'kanban_board_conversation',
      params: {
        accountId: route.params.accountId,
        boardId: selectedBoard.value.id,
        conversationId: card.conversationId,
      },
    });
  };

  const closeOpportunityDetails = () => {
    selectedOpportunityCardId.value = null;
    nextTick(() => {
      triggerElement.value?.focus?.();
      triggerElement.value = null;
    });
  };

  // The panel persists every field as it changes, so leaving it never asks.
  const exitThen = action => {
    closeOpportunityDetails();
    action?.();
  };

  const openConversationInNewTab = card => {
    if (!card?.conversationId) return;

    exitThen(() => navigateToConversationInNewTab(card));
  };

  const openConversation = (card, event = {}) => {
    if (!card?.conversationId) return;

    // A drag that ends on the card must not read as a click through to it.
    if (suppressNextCardClick.value) {
      suppressNextCardClick.value = false;
      return;
    }

    if (event.metaKey || event.ctrlKey) {
      openConversationInNewTab(card);
      return;
    }

    exitThen(() => navigateToConversation(card));
  };

  const openOpportunityInFunnel = card => {
    const boardId = boardIdForCard(card);
    if (!boardId || !card?.id) return;

    exitThen(() => {
      saveBoardSnapshot();
      router.push({
        name: 'kanban_board_show',
        params: { accountId: route.params.accountId, boardId },
        query: { card_id: card.id },
      });
    });
  };

  const copyOpportunityLink = async card => {
    const boardId = boardIdForCard(card);
    if (!boardId || !card?.id) return;

    const path = frontendURL(
      `accounts/${route.params.accountId}/kanban/${boardId}`,
      { card_id: card.id }
    );
    await copyTextToClipboard(`${window.chatwootConfig.hostURL}${path}`);
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_LINK_COPIED'));
  };

  const openDetails = card => {
    if (suppressNextCardClick.value) {
      suppressNextCardClick.value = false;
      return;
    }

    const cardElement = document.querySelector(`[data-card-id="${card.id}"]`);
    const activeElement = document.activeElement;
    triggerElement.value =
      cardElement ||
      (activeElement && activeElement !== document.body ? activeElement : null);
    selectedOpportunityCardId.value = card.id;
  };

  // A card_id in the query opens the panel once, then leaves the URL clean so a
  // reload or a back navigation does not reopen it.
  const openCardFromQuery = () => {
    const cardId = Number(route.query?.card_id);
    if (!selectedBoard.value || !Number.isInteger(cardId) || cardId <= 0) {
      return;
    }

    openDetails({ id: cardId });
    router.replace({ query: { ...route.query, card_id: undefined } });
  };

  watch([selectedBoard, () => route.query?.card_id], openCardFromQuery);

  const onOpportunityUpdated = updatedCard => {
    // Under filters an edit can move the card out of the visible set, so both
    // ends of the move are refetched instead of patched.
    if (hasActiveFilters.value) {
      refreshStageFirstPages([
        findCardStageId({ id: selectedOpportunityCardId.value }),
        updatedCard?.kanbanStageId,
      ]);
      return;
    }
    if (patchVisibleCard(updatedCard)) return;

    refreshStageFirstPage(
      findCardStageId({
        id: selectedOpportunityCardId.value,
        kanbanStageId: updatedCard?.kanbanStageId,
      })
    );
  };

  const onOpportunityBoardChanged = async ({ boardName } = {}) => {
    closeOpportunityDetails();
    await refreshSelectedBoard();
    useAlert(
      t('KANBAN.CARD.MOVE_BOARD_SUCCESS', {
        board: boardName || t('KANBAN.NO_BOARD_SELECTED'),
      })
    );
  };

  const onOpportunityRemoveCard = card => {
    closeOpportunityDetails();
    openRemoveCardConfirmation(card);
  };

  return {
    selectedOpportunityCardId,
    closeOpportunityDetails,
    copyOpportunityLink,
    onOpportunityBoardChanged,
    onOpportunityRemoveCard,
    onOpportunityUpdated,
    openConversation,
    openConversationInNewTab,
    openDetails,
    openOpportunityInFunnel,
  };
}
