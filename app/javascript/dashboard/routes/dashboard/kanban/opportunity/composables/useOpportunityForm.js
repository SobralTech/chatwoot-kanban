import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const SAVED_TIME_REFRESH_INTERVAL = 60000;

/**
 * Draft state of a single opportunity plus its dirtiness. Every other field is
 * persisted the moment it changes, so only the description is held here.
 * Knows nothing about requests or the DOM.
 */
export function useOpportunityForm({ isAdditionalDataDirty = () => false }) {
  const { t } = useI18n();

  const card = ref(null);
  const description = ref('');
  const assignableUsers = ref([]);
  const savedAt = ref(null);
  const currentTime = ref(Date.now());

  const setFormState = payload => {
    card.value = payload;
    description.value = payload.description || '';
    assignableUsers.value = payload.assignableUsers || [];
  };

  const patchCard = partial => {
    card.value = { ...(card.value || {}), ...partial };
  };

  const initial = ref({ description: description.value });

  const captureSnapshot = () => {
    initial.value = { description: description.value };
    savedAt.value = Date.now();
  };

  const dirtyFields = computed(() => ({
    description: description.value !== initial.value.description,
    additionalData: !!isAdditionalDataDirty(),
  }));

  const hasGeneralChanges = computed(() =>
    Object.values(dirtyFields.value).some(Boolean)
  );

  const hasUnsavedChanges = computed(
    () => !!card.value && hasGeneralChanges.value
  );

  const unsavedFields = computed(() =>
    [
      dirtyFields.value.description &&
        t('KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION'),
      dirtyFields.value.additionalData &&
        t('KANBAN.OPPORTUNITY_DETAILS.TABS.DETAILS'),
    ].filter(Boolean)
  );

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
    description,
    assignableUsers,
    savedAt,
    savedTimeLabel,
    dirtyFields,
    hasGeneralChanges,
    hasUnsavedChanges,
    unsavedFields,
    setFormState,
    patchCard,
    captureSnapshot,
  };
}
