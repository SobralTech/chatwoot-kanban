import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { normalizePayload } from '../opportunityPayload';

/**
 * Runs the steps in order and stops at the first failure, returning its
 * message. Sequential on purpose: the endpoints are not transactional, so a
 * later failure must not hide which part of the opportunity was persisted.
 */
const runSteps = async ([step, ...remainingSteps]) => {
  if (!step) return null;
  if (step.when && !step.when()) return runSteps(remainingSteps);

  try {
    const result = await step.run();
    step.apply?.(result);
  } catch {
    return step.errorMessage;
  }

  return runSteps(remainingSteps);
};

export function useOpportunitySave({ boardId, cardId, form, additionalData }) {
  const { t } = useI18n();

  const isSaving = ref(false);
  const saveError = ref('');
  const buildSteps = () => [
    {
      errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD'),
      when: () => form.dirtyFields.value.description,
      run: () =>
        KanbanBoardsAPI.updateCardDetailsById(boardId.value, cardId.value, {
          description: form.description.value.trim()
            ? form.description.value
            : null,
        }),
      apply: response => {
        const updatedCard = normalizePayload(response.data);
        form.patchCard(updatedCard);
        if (updatedCard.description !== undefined) {
          form.description.value = updatedCard.description || '';
        }
      },
    },
    {
      errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_FIELDS'),
      when: () => additionalData.isDirty(),
      run: async () => {
        const saved = await additionalData.save();
        if (!saved) throw new Error('additional data was not saved');
      },
    },
  ];

  const saveCard = async () => {
    if (isSaving.value || !form.hasUnsavedChanges.value) return false;

    saveError.value = '';

    isSaving.value = true;

    try {
      saveError.value = (await runSteps(buildSteps())) || '';
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
