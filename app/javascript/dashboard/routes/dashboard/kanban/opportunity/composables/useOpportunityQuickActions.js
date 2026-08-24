import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { normalizePayload } from '../opportunityPayload';

/**
 * Coordinates one optimistic opportunity update at a time per field. The
 * panel owns the field refs; this composable only owns request state,
 * rollback, response patching and the update notification.
 */
export function useOpportunityQuickActions({ patchCard, getCard, onUpdated }) {
  const { t } = useI18n();
  const pendingFields = ref(new Set());

  const isPending = field => pendingFields.value.has(field);

  const startAction = field => {
    pendingFields.value = new Set([...pendingFields.value, field]);
  };

  const endAction = field => {
    const nextPendingFields = new Set(pendingFields.value);
    nextPendingFields.delete(field);
    pendingFields.value = nextPendingFields;
  };

  const showActionError = (error, errorMessage) => {
    const message =
      typeof errorMessage === 'function' ? errorMessage(error) : errorMessage;
    useAlert(message || t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'));
  };

  const run = async (
    field,
    { request, optimistic, revert, apply, errorMessage } = {}
  ) => {
    if (isPending(field)) return false;

    startAction(field);
    optimistic?.();

    try {
      const response = await request();
      if (response === false) {
        revert?.();
        return false;
      }

      const responsePatch = apply
        ? apply(response)
        : normalizePayload(response?.data);
      if (responsePatch && !Array.isArray(responsePatch)) {
        patchCard(responsePatch);
      }
      onUpdated?.(getCard());
      return true;
    } catch (error) {
      revert?.();
      showActionError(error, errorMessage);
      return false;
    } finally {
      endAction(field);
    }
  };

  return { isPending, run };
}
