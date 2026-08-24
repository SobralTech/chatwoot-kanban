import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { normalizePayload } from '../opportunityPayload';

export function useOpportunitySave({ boardId, cardId, form, additionalData }) {
  const { t } = useI18n();

  const isSaving = ref(false);
  const saveError = ref('');

  const saveDescription = async () => {
    const response = await KanbanBoardsAPI.updateCardDetailsById(
      boardId.value,
      cardId.value,
      { description: form.description.value.trim() || null }
    );
    const updatedCard = normalizePayload(response.data);
    form.patchCard(updatedCard);
    if (updatedCard.description !== undefined) {
      form.description.value = updatedCard.description || '';
    }
  };

  // Sequential on purpose: the endpoints are not transactional, so a later
  // failure must not hide which part of the opportunity was persisted.
  const persist = async () => {
    if (form.dirtyFields.value.description) {
      try {
        await saveDescription();
      } catch {
        return t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD');
      }
    }

    if (additionalData.isDirty() && !(await additionalData.save())) {
      return t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_FIELDS');
    }

    return '';
  };

  const saveCard = async () => {
    if (isSaving.value || !form.hasUnsavedChanges.value) return false;

    saveError.value = '';
    isSaving.value = true;

    try {
      saveError.value = await persist();
      if (saveError.value) return false;

      form.captureSnapshot();
      useAlert(t('KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS'));
      return true;
    } finally {
      isSaving.value = false;
    }
  };

  return { isSaving, saveError, saveCard };
}
