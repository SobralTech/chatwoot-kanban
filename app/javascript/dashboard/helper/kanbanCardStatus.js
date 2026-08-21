import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

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
