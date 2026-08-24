import { apiErrorMessage } from './kanbanApiError';

// The board answers a refused stage or card action with a code in `error`, and
// each code has one sentence to show. Keeping the mapping here means the view
// only decides where to put the message, not how to phrase it.

export const isNameTakenError = error => {
  const errorMessage = String(apiErrorMessage(error, '')).toLowerCase();
  return errorMessage.includes('name') && errorMessage.includes('taken');
};

export const isSpecialStageOrderError = error =>
  error?.response?.data?.error === 'special_stages_must_be_last';

export const isLostReasonRequiredError = error =>
  error?.response?.data?.error === 'lost_reason_required';

// A blocked bulk move reports how many cards each reason stopped, so the count
// leads and the reasons follow it.
const stageCardsBlockedMessage = (error, t) => {
  const blocked = error?.response?.data?.blocked || {};
  const duplicateCount = Number(blocked.card_already_in_target_board || 0);
  const inboxCount = Number(blocked.inbox_not_allowed || 0);
  const count = duplicateCount + inboxCount;
  const details = [
    duplicateCount
      ? t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED_DUPLICATE', {
          count: duplicateCount,
        })
      : null,
    inboxCount
      ? t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED_INBOX', {
          count: inboxCount,
        })
      : null,
  ].filter(Boolean);

  return [
    t('KANBAN.STAGE_MENU.ERRORS.STAGE_CARDS_BLOCKED', { count }),
    ...details,
  ].join(' ');
};

export const stageActionErrorMessage = (error, { t, selectionLimit }) => {
  switch (error?.response?.data?.error) {
    case 'stage_not_empty':
      return t('KANBAN.STAGE_MENU.ERRORS.STAGE_NOT_EMPTY');
    case 'stage_cards_blocked':
      return stageCardsBlockedMessage(error, t);
    case 'stage_name_taken':
      return t('KANBAN.STAGE_MENU.ERRORS.STAGE_NAME_TAKEN');
    case 'last_stage_cannot_move_board':
      return t('KANBAN.STAGE_MENU.ERRORS.LAST_STAGE_CANNOT_MOVE_BOARD');
    case 'special_stage_cannot_move_board':
      return t('KANBAN.STAGE_MENU.ERRORS.SPECIAL_STAGE_CANNOT_MOVE_BOARD');
    case 'special_stage_cannot_be_deleted':
      return t('KANBAN.ACTIONS.REMOVE_STAGE_TERMINAL');
    case 'terminal_stage_not_allowed':
      return t('KANBAN.STAGE_MENU.ERRORS.TERMINAL_STAGE_NOT_ALLOWED');
    case 'bulk_action_limit_exceeded':
      return t('KANBAN.STAGE_MENU.ERRORS.MOVE_CARDS_LIMIT', {
        count: selectionLimit,
      });
    default:
      return null;
  }
};

// The one sentence to show for a refused board action, most specific first.
export const kanbanActionErrorMessage = (
  error,
  fallbackMessage,
  { t, selectionLimit }
) => {
  const stageMessage = stageActionErrorMessage(error, { t, selectionLimit });
  if (stageMessage) return stageMessage;
  if (isSpecialStageOrderError(error)) {
    return t('KANBAN.ACTIONS.STAGE_ORDER_INVALID');
  }
  if (isNameTakenError(error)) return t('KANBAN.ACTIONS.STAGE_NAME_TAKEN');

  return apiErrorMessage(error, fallbackMessage);
};
