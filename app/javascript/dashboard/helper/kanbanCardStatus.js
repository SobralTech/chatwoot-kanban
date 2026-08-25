import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

// The board payload is camelized, but the card specs still feed the raw column
// name. Both spellings resolve here, and only here.
export const reasonsOfType = (reasons, type) =>
  (reasons || []).filter(
    reason => (reason.reason_type ?? reason.reasonType) === type
  );

export const isDirectWonLostTransitionError = error =>
  error?.response?.data?.error === 'direct_won_lost_transition_not_allowed';

export const getCardStatusChangeErrorMessage = (error, { reopen, t }) => {
  if (isDirectWonLostTransitionError(error)) {
    return t('KANBAN.CARD.STATUS.DIRECT_WON_LOST_TRANSITION_NOT_ALLOWED');
  }

  return apiErrorMessage(
    error,
    t(
      reopen
        ? 'KANBAN.CARD.STATUS.REOPEN_ERROR'
        : 'KANBAN.CARD.STATUS.UPDATE_ERROR'
    )
  );
};
