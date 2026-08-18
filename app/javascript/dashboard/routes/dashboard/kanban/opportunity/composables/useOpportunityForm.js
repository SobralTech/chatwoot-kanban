import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { formatDateInput } from 'dashboard/helper/kanbanDueDate';

const SAVED_TIME_REFRESH_INTERVAL = 60000;

/**
 * Editable state of a single opportunity plus its per-field dirtiness.
 * Knows nothing about requests or the DOM: the panel loads the card, this
 * decides what changed and what the save bar should say.
 */
export function useOpportunityForm({ isAdditionalDataDirty = () => false }) {
  const { t } = useI18n();

  const card = ref(null);
  const subject = ref('');
  const description = ref('');
  const dueAt = ref('');
  const priority = ref('');
  const selectedLabelTitles = ref([]);
  const assignedUsers = ref([]);
  const assignableUsers = ref([]);
  const savedAt = ref(null);
  const currentTime = ref(Date.now());

  const selectedAssigneeIds = computed(() =>
    assignedUsers.value.map(user => user.id)
  );

  const setFormState = payload => {
    card.value = payload;
    subject.value = payload.subject || '';
    description.value = payload.description || '';
    dueAt.value = formatDateInput(payload.dueAt);
    priority.value = payload.priority || '';
  };

  const patchCard = partial => {
    card.value = { ...(card.value || {}), ...partial };
  };

  const setEmbeddedContext = payload => {
    selectedLabelTitles.value = (payload.labels || []).map(
      label => label.title || label
    );
    assignedUsers.value = payload.assignees || [];
    assignableUsers.value = payload.assignableUsers || [];
  };

  const addLabel = label => {
    const title = label?.title || label;
    if (!title || selectedLabelTitles.value.includes(title)) return;

    selectedLabelTitles.value = [...selectedLabelTitles.value, title];
  };

  const removeLabel = title => {
    selectedLabelTitles.value = selectedLabelTitles.value.filter(
      selectedTitle => selectedTitle !== title
    );
  };

  const toggleAssignee = user => {
    assignedUsers.value = selectedAssigneeIds.value.includes(user.id)
      ? assignedUsers.value.filter(existing => existing.id !== user.id)
      : [...assignedUsers.value, user];
  };

  const buildFormState = () => ({
    subject: subject.value,
    description: description.value,
    dueAt: dueAt.value,
    priority: priority.value,
    labels: [...selectedLabelTitles.value].sort().join('|'),
    assigneeIds: [...selectedAssigneeIds.value]
      .map(Number)
      .sort((a, b) => a - b)
      .join('|'),
  });

  const initial = ref(buildFormState());

  const captureSnapshot = () => {
    initial.value = buildFormState();
    savedAt.value = Date.now();
  };

  const dirtyFields = computed(() => {
    const current = buildFormState();
    const changed = field => current[field] !== initial.value[field];

    return {
      subject: changed('subject'),
      description: changed('description'),
      dueAt: changed('dueAt'),
      priority: changed('priority'),
      labels: changed('labels'),
      assignees: changed('assigneeIds'),
      additionalData: !!isAdditionalDataDirty(),
    };
  });

  const hasGeneralChanges = computed(() =>
    Object.entries(dirtyFields.value).some(
      ([field, isDirty]) => field !== 'additionalData' && isDirty
    )
  );

  const hasUnsavedChanges = computed(
    () => !!card.value && Object.values(dirtyFields.value).some(Boolean)
  );

  const unsavedFields = computed(() => {
    const dirty = dirtyFields.value;

    return [
      dirty.subject && t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE'),
      dirty.description && t('KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION'),
      dirty.priority && t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY'),
      dirty.dueAt && t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE'),
      dirty.labels && t('KANBAN.OPPORTUNITY_DETAILS.LABELS'),
      dirty.assignees && t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE'),
      dirty.additionalData &&
        t('KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA'),
    ].filter(Boolean);
  });

  const savedTimeLabel = computed(() => {
    if (!savedAt.value) return '';

    const elapsedSeconds = Math.max(
      0,
      (currentTime.value - savedAt.value) / 1000
    );
    const relativeTime = new Intl.RelativeTimeFormat(undefined, {
      numeric: 'auto',
    });

    if (elapsedSeconds < 60) return relativeTime.format(0, 'second');
    if (elapsedSeconds < 3600) {
      return relativeTime.format(-Math.floor(elapsedSeconds / 60), 'minute');
    }
    if (elapsedSeconds < 86400) {
      return relativeTime.format(-Math.floor(elapsedSeconds / 3600), 'hour');
    }

    return relativeTime.format(-Math.floor(elapsedSeconds / 86400), 'day');
  });

  let savedTimeTimer = null;

  onMounted(() => {
    savedTimeTimer = setInterval(() => {
      currentTime.value = Date.now();
    }, SAVED_TIME_REFRESH_INTERVAL);
  });

  onUnmounted(() => clearInterval(savedTimeTimer));

  return {
    card,
    subject,
    description,
    dueAt,
    priority,
    selectedLabelTitles,
    assignedUsers,
    assignableUsers,
    selectedAssigneeIds,
    savedAt,
    savedTimeLabel,
    dirtyFields,
    hasGeneralChanges,
    hasUnsavedChanges,
    unsavedFields,
    setFormState,
    setEmbeddedContext,
    patchCard,
    addLabel,
    removeLabel,
    toggleAssignee,
    captureSnapshot,
  };
}
