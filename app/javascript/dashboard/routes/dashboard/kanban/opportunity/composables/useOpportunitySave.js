import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import { useAlert } from 'dashboard/composables';
import { toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { normalizePayload } from '../opportunityPayload';

const labelsPayload = response =>
  response?.data?.payload || response?.data || [];

/**
 * Runs the steps in order and stops at the first failure, returning its
 * message. Sequential on purpose: the endpoints are not transactional, so a
 * later failure must not hide which part of the opportunity was persisted.
 */
const runSteps = async ([step, ...remainingSteps]) => {
  if (!step) return null;
  if (step.when && !step.when()) return runSteps(remainingSteps);

  try {
    step.apply?.(await step.run());
  } catch {
    return step.errorMessage;
  }

  return runSteps(remainingSteps);
};

export function useOpportunitySave({ boardId, cardId, form, additionalData }) {
  const { t } = useI18n();

  const isSaving = ref(false);
  const saveError = ref('');
  const subjectError = ref('');

  const buildSteps = subject => [
    {
      errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_CARD'),
      run: () =>
        KanbanBoardsAPI.updateCardDetailsById(boardId.value, cardId.value, {
          subject,
          description: form.description.value.trim()
            ? form.description.value
            : null,
          due_at: toIso8601(form.dueAt.value),
          priority: form.priority.value || null,
        }),
      apply: response =>
        form.setFormState({
          ...(form.card.value || {}),
          ...normalizePayload(response.data),
        }),
    },
    {
      errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_LABELS'),
      run: () =>
        KanbanBoardsAPI.updateCardLabels(
          boardId.value,
          cardId.value,
          form.selectedLabelTitles.value
        ),
      apply: response => {
        form.selectedLabelTitles.value = normalizePayload(
          labelsPayload(response)
        ).map(label => label.title || label);
      },
    },
    {
      errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SAVE_STEP_ERROR_ASSIGNEES'),
      run: () =>
        KanbanBoardsAPI.updateCardAssignees(
          boardId.value,
          cardId.value,
          form.selectedAssigneeIds.value
        ),
      apply: response => {
        const payload = normalizePayload(response?.data);
        form.assignedUsers.value = payload.payload || [];
        form.assignableUsers.value =
          payload.assignableUsers || form.assignableUsers.value;
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

    const subject = form.subject.value.trim();
    subjectError.value = '';
    saveError.value = '';

    if (!subject) {
      subjectError.value = t('KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE');
      return false;
    }

    isSaving.value = true;

    try {
      saveError.value = (await runSteps(buildSteps(subject))) || '';
      if (saveError.value) return false;

      form.captureSnapshot();
      useAlert(t('KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS'));
      return true;
    } finally {
      isSaving.value = false;
    }
  };

  return { isSaving, saveError, subjectError, saveCard };
}
