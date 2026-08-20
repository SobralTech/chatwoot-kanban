<script setup>
import { computed, onMounted, reactive, ref, shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import ColorPicker from 'dashboard/components-next/colorpicker/ColorPicker.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import AgentTagInput from 'dashboard/components-next/taginput/AgentTagInput.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { DEFAULT_KANBAN_STAGE_COLOR } from 'dashboard/helper/kanbanStageColors';
import KanbanStageEditPanel from './KanbanStageEditPanel.vue';
import KanbanBoardTemplatePicker from './KanbanBoardTemplatePicker.vue';
import KanbanCustomFieldsTab from './KanbanCustomFieldsTab.vue';
import KanbanReasonsTab from './KanbanReasonsTab.vue';

const TAB_KEYS = ['stages', 'custom_fields', 'settings', 'reasons'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const inboxes = useMapGetter('inboxes/getAllInboxes');
const { isAdmin } = useAdmin();

const boardId = ref(route.params.boardId ? Number(route.params.boardId) : null);

const isLoading = ref(true);
const isTogglingActive = ref(false);
const isDiscarding = ref(false);
const isSavingSettings = ref(false);
const isSavingAutomation = ref(false);
const isDeleting = ref(false);
const isCreatingStage = ref(false);
const isUpdatingStage = ref(false);
const isRemovingStage = ref(false);
const isImportingConversations = ref(false);

const loadError = ref('');
const stageError = ref('');
const importError = ref('');

const showDeleteConfirmation = ref(false);
const showCreateStageForm = ref(false);
const showImportExistingConversationsModal = ref(false);
const showRemoveStageConfirmation = ref(false);
const showDiscardSettingsConfirmation = ref(false);
const showUnsavedChangesModal = ref(false);
const showDiscardDraftModal = ref(false);

const stages = ref([]);
const newStageName = ref('');
const newStageDescription = ref('');
const newStageColor = ref(DEFAULT_KANBAN_STAGE_COLOR);
const newStageSlaHours = ref(null);
const editingStageId = ref(null);
const editStageName = ref('');
const editStageDescription = ref('');
const editStageColor = ref(DEFAULT_KANBAN_STAGE_COLOR);
const editStageSlaHours = ref(null);
const stagePendingRemoval = ref(null);
const ignoreGroupsForImport = ref(false);
const stageReconcileWarning = ref('');

const activeTabIndex = ref(0);
const isFreshDraft = ref(false);
const templates = ref([]);
const isCreatingTemplate = ref(false);
const isTemplatePickerVisible = computed(
  () => route.name === 'kanban_board_create_form'
);
const savedSnapshot = shallowRef(null);
const pendingNavigation = ref(null);

const form = reactive({
  name: '',
  description: '',
  active: false,
  autoCreateCardsFromConversations: false,
  visibilityMode: 'all_agents',
  visibleUserIds: [],
  inboxScopeMode: 'all_inboxes',
  allowedInboxIds: [],
  wonStageId: null,
  lostStageId: null,
  lostReasonRequired: false,
  wonRecurrenceEnabled: false,
  wonRecurrenceWindowHours: null,
  lostRecurrenceEnabled: false,
  lostRecurrenceWindowHours: null,
});

const { isTerminalStage, isWonStage, regularStages, terminalStages } =
  useKanbanStageOrder({
    stages,
    wonStageId: computed(() => form.wonStageId),
    lostStageId: computed(() => form.lostStageId),
  });
// Tailwind needs literal class names, so the won/lost accents live in one map
// instead of being re-derived at every binding.
const TERMINAL_STAGE_CLASSES = {
  won: {
    panel: 'border-n-teal-8 bg-n-teal-2',
    dot: 'bg-n-teal-9',
    label: 'text-n-teal-11',
  },
  lost: {
    panel: 'border-n-ruby-8 bg-n-ruby-2',
    dot: 'bg-n-ruby-9',
    label: 'text-n-ruby-11',
  },
};
const terminalStageClasses = stage =>
  isWonStage(stage) ? TERMINAL_STAGE_CLASSES.won : TERMINAL_STAGE_CLASSES.lost;
const stageListModel = computed({
  get: () => regularStages.value,
  set: nextStages => {
    stages.value = [...nextStages, ...terminalStages.value];
  },
});
const buildStageSelectOptions = availableStages => [
  {
    value: '',
    label: t('KANBAN.BOARD_EDIT.STAGES_TAB.SELECT_STAGE_PLACEHOLDER'),
  },
  ...availableStages.map(stage => ({ value: stage.id, label: stage.name })),
];
const wonStageOptions = computed(() =>
  buildStageSelectOptions(
    stages.value.filter(stage => stage.id !== form.lostStageId)
  )
);
const lostStageOptions = computed(() =>
  buildStageSelectOptions(
    stages.value.filter(stage => stage.id !== form.wonStageId)
  )
);
const hasStageSelectionConflict = computed(
  () =>
    form.wonStageId && form.lostStageId && form.wonStageId === form.lostStageId
);

const tabItems = computed(() => [
  { label: t('KANBAN.BOARD_EDIT.TABS.STAGES') },
  { label: t('KANBAN.BOARD_EDIT.TABS.CUSTOM_FIELDS') },
  { label: t('KANBAN.BOARD_EDIT.TABS.SETTINGS') },
  { label: t('KANBAN.BOARD_EDIT.TABS.REASONS') },
]);
const activeTabKey = computed(() => TAB_KEYS[activeTabIndex.value]);

const pageTitle = computed(() =>
  route.name === 'kanban_board_create_form' || isFreshDraft.value
    ? t('KANBAN.BOARD_EDIT.CREATE_TITLE')
    : t('KANBAN.BOARD_EDIT.EDIT_TITLE', { name: form.name })
);

const canActivate = computed(() => !!(form.wonStageId && form.lostStageId));
const saveDisabled = computed(
  () =>
    isLoading.value ||
    !!loadError.value ||
    isSavingSettings.value ||
    !form.name.trim()
);

const backDestination = computed(() =>
  boardId.value && !isFreshDraft.value
    ? {
        name: 'kanban_board_show',
        params: { accountId: route.params.accountId, boardId: boardId.value },
      }
    : { name: 'kanban_boards', params: { accountId: route.params.accountId } }
);

const backLabel = computed(() =>
  backDestination.value.name === 'kanban_boards'
    ? t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')
    : t('KANBAN.ACTIONS.BACK_TO_BOARD')
);

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);

const getErrorMessage = (error, fallbackMessage) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallbackMessage;

const normalizeForDiff = source => ({
  name: (source.name || '').trim(),
  description: (source.description || '').trim(),
  visibilityMode: source.visibilityMode,
  visibleUserIds: [...(source.visibleUserIds || [])].sort((a, b) => a - b),
  inboxScopeMode: source.inboxScopeMode,
  allowedInboxIds: [...(source.allowedInboxIds || [])].sort((a, b) => a - b),
  wonStageId: source.wonStageId ?? null,
  lostStageId: source.lostStageId ?? null,
  lostReasonRequired: !!source.lostReasonRequired,
  wonRecurrenceEnabled: !!source.wonRecurrenceEnabled,
  wonRecurrenceWindowHours: source.wonRecurrenceWindowHours ?? null,
  lostRecurrenceEnabled: !!source.lostRecurrenceEnabled,
  lostRecurrenceWindowHours: source.lostRecurrenceWindowHours ?? null,
});

const isDirty = computed(
  () =>
    !!savedSnapshot.value &&
    JSON.stringify(normalizeForDiff(form)) !==
      JSON.stringify(savedSnapshot.value)
);

const applySettings = payload => {
  const settings = camelcaseKeys(payload || {}, { deep: true });

  form.name = settings.name || '';
  form.description = settings.description || '';
  form.active = settings.active || false;
  form.autoCreateCardsFromConversations =
    settings.autoCreateCardsFromConversations || false;
  form.visibilityMode = settings.visibilityMode || 'all_agents';
  form.visibleUserIds = settings.visibleUserIds || [];
  form.inboxScopeMode = settings.inboxScopeMode || 'all_inboxes';
  form.allowedInboxIds = settings.allowedInboxIds || [];
  form.wonStageId = settings.wonStageId ?? null;
  form.lostStageId = settings.lostStageId ?? null;
  form.lostReasonRequired = settings.lostReasonRequired || false;
  form.wonRecurrenceEnabled = settings.wonRecurrenceEnabled || false;
  form.wonRecurrenceWindowHours = settings.wonRecurrenceWindowHours ?? null;
  form.lostRecurrenceEnabled = settings.lostRecurrenceEnabled || false;
  form.lostRecurrenceWindowHours = settings.lostRecurrenceWindowHours ?? null;

  savedSnapshot.value = normalizeForDiff(form);
};

const applyBoard = payload => {
  const board = camelcaseKeys(payload || {}, { deep: true });
  stages.value = board.stages || [];
};

const reconcileDraftStages = () => {
  const ids = new Set(stages.value.map(stage => stage.id));
  if (form.wonStageId && !ids.has(form.wonStageId)) {
    form.wonStageId = null;
    stageReconcileWarning.value = t('KANBAN.BOARD_EDIT.WON_STAGE_REMOVED');
  }
  if (form.lostStageId && !ids.has(form.lostStageId)) {
    form.lostStageId = null;
    stageReconcileWarning.value = t('KANBAN.BOARD_EDIT.LOST_STAGE_REMOVED');
  }
};

const refreshBoard = async () => {
  const response = await KanbanBoardsAPI.showBoard(boardId.value);
  applyBoard(response.data);
  reconcileDraftStages();
};

const loadBoard = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const [settingsResponse, boardResponse] = await Promise.all([
      KanbanBoardsAPI.getSettings(boardId.value),
      KanbanBoardsAPI.showBoard(boardId.value),
      store.dispatch('agents/get'),
      store.dispatch('inboxes/get'),
    ]);
    applySettings(settingsResponse.data);
    applyBoard(boardResponse.data);
    reconcileDraftStages();
  } catch (error) {
    loadError.value = getErrorMessage(error, t('KANBAN.BOARD_EDIT.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const loadTemplates = async () => {
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.templates();
    templates.value = camelcaseKeys(response.data || [], { deep: true });
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.BOARD_TEMPLATES.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const ensureDraftBoard = async templateKey => {
  if (route.name !== 'kanban_board_create_form') return;

  isCreatingTemplate.value = true;
  loadError.value = '';

  try {
    await store.dispatch('kanbanBoards/fetchBoards');
    const position = store.getters['kanbanBoards/kanbanBoards'].length;
    const response = await KanbanBoardsAPI.create({
      template_key: templateKey,
      kanban_board: {
        name: t('KANBAN.BOARD_EDIT.NEW_BOARD_DEFAULT_NAME'),
        active: false,
        position,
      },
    });
    const created = camelcaseKeys(response.data || {}, { deep: true });
    boardId.value = created.id;
    isFreshDraft.value = true;

    await router.replace({
      name: 'kanban_board_edit_form',
      params: {
        accountId: route.params.accountId,
        boardId: boardId.value,
      },
    });
    await loadBoard();
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.BOARD_EDIT.CREATE_ERROR')
    );
  } finally {
    isCreatingTemplate.value = false;
  }
};

const buildSettingsPayload = () => ({
  kanban_board: {
    name: form.name.trim(),
    description: form.description.trim(),
    visibility_mode: form.visibilityMode,
    visible_user_ids:
      form.visibilityMode === 'selected_agents' ? form.visibleUserIds : [],
    inbox_scope_mode: form.inboxScopeMode,
    allowed_inbox_ids:
      form.inboxScopeMode === 'selected_inboxes' ? form.allowedInboxIds : [],
    won_stage_id: form.wonStageId,
    lost_stage_id: form.lostStageId,
    lost_reason_required: form.lostReasonRequired,
    won_recurrence_enabled: form.wonRecurrenceEnabled,
    won_recurrence_window_hours: form.wonRecurrenceWindowHours,
    lost_recurrence_enabled: form.lostRecurrenceEnabled,
    lost_recurrence_window_hours: form.lostRecurrenceWindowHours,
  },
});

const persistSettings = async () => {
  if (!form.name.trim() || !isAdmin.value || isSavingSettings.value) {
    return false;
  }

  isSavingSettings.value = true;

  try {
    const response = await KanbanBoardsAPI.updateSettings(
      boardId.value,
      buildSettingsPayload()
    );
    applySettings(response.data);
    await Promise.all([
      refreshBoard(),
      store.dispatch('kanbanBoards/refreshBoards'),
    ]);
    return true;
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR')));
    return false;
  } finally {
    isSavingSettings.value = false;
  }
};

const onVisibleUserIdsChange = userIds => {
  form.visibleUserIds = userIds;
  form.visibilityMode = userIds.length ? 'selected_agents' : 'all_agents';
};

const onWonStageChange = value => {
  const nextStageId = value ? Number(value) : null;
  if (nextStageId && nextStageId === form.lostStageId) {
    stageError.value = t(
      'KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_SELECTION_CONFLICT'
    );
    return;
  }

  form.wonStageId = nextStageId;
};

const onLostStageChange = value => {
  const nextStageId = value ? Number(value) : null;
  if (nextStageId && nextStageId === form.wonStageId) {
    stageError.value = t(
      'KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_SELECTION_CONFLICT'
    );
    return;
  }

  form.lostStageId = nextStageId;
};

const onWonRecurrenceWindowHoursChange = value => {
  form.wonRecurrenceWindowHours = value === '' ? null : Number(value);
};

const onLostRecurrenceWindowHoursChange = value => {
  form.lostRecurrenceWindowHours = value === '' ? null : Number(value);
};

const onAutoCreateChange = async checked => {
  if (isSavingAutomation.value || !isAdmin.value) return;

  form.autoCreateCardsFromConversations = checked;
  isSavingAutomation.value = true;

  try {
    const response = await KanbanBoardsAPI.updateSettings(boardId.value, {
      kanban_board: {
        auto_create_cards_from_conversations: checked,
      },
    });
    const settings = camelcaseKeys(response.data || {}, { deep: true });
    form.autoCreateCardsFromConversations =
      settings.autoCreateCardsFromConversations ?? checked;
    await store.dispatch('kanbanBoards/refreshBoards');

    if (checked) {
      importError.value = '';
      ignoreGroupsForImport.value = false;
      showImportExistingConversationsModal.value = true;
    }
  } catch (error) {
    form.autoCreateCardsFromConversations = !checked;
    useAlert(getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR')));
  } finally {
    isSavingAutomation.value = false;
  }
};

const closeImportExistingConversationsModal = () => {
  if (isImportingConversations.value) return;

  showImportExistingConversationsModal.value = false;
  importError.value = '';
};

const importExistingConversations = async () => {
  if (isImportingConversations.value) return;

  isImportingConversations.value = true;
  importError.value = '';

  try {
    await KanbanBoardsAPI.importExistingConversations(boardId.value, {
      ignore_groups: ignoreGroupsForImport.value,
    });
    showImportExistingConversationsModal.value = false;
    useAlert(t('KANBAN.SETTINGS.AUTOMATIONS.IMPORT_SUCCESS'));
  } catch (error) {
    importError.value = getErrorMessage(
      error,
      t('KANBAN.SETTINGS.AUTOMATIONS.IMPORT_ERROR')
    );
    useAlert(importError.value);
  } finally {
    isImportingConversations.value = false;
  }
};

const getStageCardsCount = stage =>
  stage.cardsCount ?? stage.cards?.length ?? 0;

const openCreateStageForm = () => {
  showCreateStageForm.value = true;
};

const closeCreateStageForm = () => {
  showCreateStageForm.value = false;
  newStageName.value = '';
  newStageDescription.value = '';
  newStageColor.value = DEFAULT_KANBAN_STAGE_COLOR;
  newStageSlaHours.value = null;
};

const createStage = async () => {
  const name = newStageName.value.trim();
  if (!name || isCreatingStage.value || !isAdmin.value) return;

  isCreatingStage.value = true;
  stageError.value = '';

  try {
    const stagePayload = {
      name,
      description: newStageDescription.value.trim(),
      color: newStageColor.value,
      position: regularStages.value.length + 1,
    };
    if (newStageSlaHours.value !== '' && newStageSlaHours.value !== null) {
      stagePayload.sla_hours = Number(newStageSlaHours.value);
    }

    await KanbanBoardsAPI.createStage(boardId.value, { stage: stagePayload });
    closeCreateStageForm();
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
    useAlert(t('KANBAN.ACTIONS.CREATE_STAGE_SUCCESS'));
  } catch (error) {
    stageError.value = getErrorMessage(
      error,
      t('KANBAN.ACTIONS.CREATE_STAGE_ERROR')
    );
    useAlert(stageError.value);
  } finally {
    isCreatingStage.value = false;
  }
};

const openEditStage = stage => {
  editingStageId.value = stage.id;
  editStageName.value = stage.name;
  editStageDescription.value = stage.description || '';
  editStageColor.value = stage.color;
  editStageSlaHours.value = stage.slaHours ?? null;
};

const closeEditStage = () => {
  editingStageId.value = null;
  editStageName.value = '';
  editStageDescription.value = '';
  editStageColor.value = DEFAULT_KANBAN_STAGE_COLOR;
  editStageSlaHours.value = null;
};

const updateStage = async stage => {
  const name = editStageName.value.trim();
  if (!name || isUpdatingStage.value || !isAdmin.value) return;

  isUpdatingStage.value = true;
  stageError.value = '';

  try {
    const stagePayload = {
      name,
      description: editStageDescription.value.trim(),
    };
    if (!isTerminalStage(stage)) {
      stagePayload.color = editStageColor.value;
      if (
        (stage.slaHours !== null && stage.slaHours !== undefined) ||
        (editStageSlaHours.value !== '' && editStageSlaHours.value !== null)
      ) {
        stagePayload.sla_hours =
          editStageSlaHours.value === '' || editStageSlaHours.value === null
            ? null
            : Number(editStageSlaHours.value);
      }
    }

    await KanbanBoardsAPI.updateStage(boardId.value, stage.id, {
      stage: stagePayload,
    });
    closeEditStage();
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
    useAlert(t('KANBAN.ACTIONS.UPDATE_STAGE_SUCCESS'));
  } catch (error) {
    stageError.value = getErrorMessage(
      error,
      t('KANBAN.ACTIONS.UPDATE_STAGE_ERROR')
    );
    useAlert(stageError.value);
  } finally {
    isUpdatingStage.value = false;
  }
};

const openRemoveStageConfirmation = stage => {
  if (getStageCardsCount(stage) > 0) {
    stageError.value = t('KANBAN.ACTIONS.REMOVE_STAGE_NOT_EMPTY');
    useAlert(stageError.value);
    return;
  }

  stagePendingRemoval.value = stage;
  showRemoveStageConfirmation.value = true;
};

const closeRemoveStageConfirmation = () => {
  showRemoveStageConfirmation.value = false;
  stagePendingRemoval.value = null;
};

const removeStage = async () => {
  const stage = stagePendingRemoval.value;
  if (!stage || isRemovingStage.value || !isAdmin.value) return;

  isRemovingStage.value = true;
  stageError.value = '';

  try {
    await KanbanBoardsAPI.deleteStage(boardId.value, stage.id);
    closeRemoveStageConfirmation();
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
    useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
  } catch (error) {
    const errorCode = error?.response?.data?.error;
    if (errorCode === 'special_stage_cannot_be_deleted') {
      stageError.value = t('KANBAN.ACTIONS.REMOVE_STAGE_TERMINAL');
    } else if (error?.response?.status === 422) {
      stageError.value = t('KANBAN.ACTIONS.REMOVE_STAGE_NOT_EMPTY');
    } else {
      stageError.value = getErrorMessage(
        error,
        t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR')
      );
    }
    useAlert(stageError.value);
    await refreshBoard();
  } finally {
    isRemovingStage.value = false;
  }
};

const reorderStageByPosition = async (stage, position) => {
  if (!stage?.id || !isAdmin.value) return;

  stageError.value = '';

  try {
    await KanbanBoardsAPI.reorderStage(boardId.value, stage.id, { position });
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
  } catch (error) {
    stageError.value = getErrorMessage(
      error,
      t('KANBAN.ACTIONS.REORDER_STAGE_ERROR')
    );
    useAlert(stageError.value);
    await refreshBoard();
  }
};

const onStageDragEnd = async event => {
  const stageId = Number(event?.item?.dataset?.stageId);
  const newIndex = event?.newIndex;
  const oldIndex = event?.oldIndex;
  if (!stageId || oldIndex === newIndex || newIndex === undefined) return;

  const stage = stages.value.find(item => item.id === stageId);
  if (!stage) return;

  await reorderStageByPosition(stage, newIndex + 1);
};

const onActiveToggle = async () => {
  if (isTogglingActive.value) return;

  const desired = form.active;
  isTogglingActive.value = true;

  try {
    const response = await KanbanBoardsAPI.update(boardId.value, {
      kanban_board: { active: desired },
    });
    form.active = camelcaseKeys(response.data || {}, { deep: true }).active;
    if (form.active) isFreshDraft.value = false;
    await store.dispatch('kanbanBoards/refreshBoards');
  } catch (error) {
    form.active = !desired;
    useAlert(
      desired
        ? t('KANBAN.BOARD_EDIT.ACTIVATE_ERROR')
        : getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR'))
    );
  } finally {
    isTogglingActive.value = false;
  }
};

const goBack = () => router.push(backDestination.value);

// Closes whichever leave-guard modal is open and settles the navigation it
// intercepted: `proceed` lets the router continue, otherwise it is cancelled.
const resolveNavigation = proceed => {
  showUnsavedChangesModal.value = false;
  showDiscardDraftModal.value = false;

  const next = pendingNavigation.value;
  pendingNavigation.value = null;

  if (!next) return;
  if (proceed) next();
  else next(false);
};

const keepEditing = () => resolveNavigation(false);

const restoreSavedSettings = () => {
  if (savedSnapshot.value)
    Object.assign(form, normalizeForDiff(savedSnapshot.value));
};

const discardSettings = () => {
  restoreSavedSettings();
  showDiscardSettingsConfirmation.value = false;
};

const discardChangesAndExit = () => {
  restoreSavedSettings();
  resolveNavigation(true);
};

const saveAndExit = async () => {
  resolveNavigation(await persistSettings());
};

const discardDraft = async () => {
  if (isDiscarding.value || !boardId.value) return;

  isDiscarding.value = true;

  try {
    await KanbanBoardsAPI.delete(boardId.value);
    await store.dispatch('kanbanBoards/refreshBoards');
    resolveNavigation(true);
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.BOARD_EDIT.DISCARD_ERROR')));
  } finally {
    isDiscarding.value = false;
  }
};

const openDeleteConfirmation = () => {
  showDeleteConfirmation.value = true;
};

const closeDeleteConfirmation = () => {
  showDeleteConfirmation.value = false;
};

const deleteBoard = async () => {
  if (isDeleting.value || !isAdmin.value) return;

  isDeleting.value = true;

  try {
    await KanbanBoardsAPI.delete(boardId.value);
    await store.dispatch('kanbanBoards/refreshBoards');
    closeDeleteConfirmation();
    await router.replace({
      name: 'kanban_boards',
      params: { accountId: route.params.accountId },
    });
    useAlert(t('KANBAN.ACTIONS.REMOVE_BOARD_SUCCESS'));
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.ACTIONS.REMOVE_BOARD_ERROR')));
  } finally {
    isDeleting.value = false;
  }
};

const onTabChanged = tab => {
  const index = tabItems.value.findIndex(item => item.label === tab.label);
  if (index !== -1) activeTabIndex.value = index;
};

useEventListener(window, 'beforeunload', event => {
  if (!isDirty.value) return;

  event.preventDefault();
  event.returnValue = '';
});

onBeforeRouteLeave((to, from, next) => {
  // The draft's own create -> edit redirect is not a real exit.
  if (
    to.name === 'kanban_board_edit_form' &&
    Number(to.params.boardId) === boardId.value
  ) {
    next();
    return;
  }

  if (isFreshDraft.value && !form.active) {
    pendingNavigation.value = next;
    showDiscardDraftModal.value = true;
    return;
  }

  if (!isDirty.value) {
    next();
    return;
  }

  pendingNavigation.value = next;
  showUnsavedChangesModal.value = true;
});

onMounted(async () => {
  if (route.name === 'kanban_board_create_form') {
    await loadTemplates();
    return;
  }

  if (loadError.value || !boardId.value) {
    isLoading.value = false;
    return;
  }

  await loadBoard();
});
</script>

<template>
  <main
    class="flex h-full min-h-0 w-full flex-col bg-n-surface-1 text-n-slate-12"
  >
    <header
      class="flex flex-none items-center justify-between gap-4 border-b border-n-weak px-6 py-4"
    >
      <Button
        data-testid="kanban-board-form-back"
        icon="i-lucide-chevron-left"
        variant="ghost"
        color="slate"
        size="md"
        class="[&>span]:size-5"
        :aria-label="backLabel"
        :title="backLabel"
        @click="goBack"
      />
      <template v-if="!isTemplatePickerVisible">
        <div class="flex min-w-0 flex-1 items-center gap-2">
          <h1 class="min-w-0 truncate text-lg font-medium text-n-slate-12">
            {{ pageTitle }}
          </h1>
          <span
            v-if="isDirty"
            data-testid="kanban-board-form-unsaved-indicator"
            class="flex-none rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            {{ t('KANBAN.BOARD_EDIT.UNSAVED_INDICATOR') }}
          </span>
        </div>
        <div class="flex flex-none items-center gap-2">
          <Button
            v-if="isDirty"
            data-testid="kanban-board-form-discard"
            icon="i-lucide-x"
            variant="outline"
            color="slate"
            size="sm"
            :label="t('KANBAN.BOARD_EDIT.DISCARD')"
            @click="showDiscardSettingsConfirmation = true"
          />
          <Button
            v-if="isDirty"
            data-testid="kanban-board-form-save"
            icon="i-lucide-check"
            color="blue"
            size="sm"
            :label="t('KANBAN.BOARD_EDIT.SAVE')"
            :disabled="saveDisabled"
            :is-loading="isSavingSettings"
            @click="persistSettings"
          />
        </div>
      </template>
    </header>

    <template v-if="!isTemplatePickerVisible">
      <p
        v-if="!isLoading && !loadError && !form.active && !canActivate"
        data-testid="kanban-board-form-locked-help"
        class="flex-none border-b border-n-weak bg-n-amber-2 px-6 py-2 text-sm text-n-amber-11"
      >
        {{ t('KANBAN.BOARD_EDIT.ACTIVATE_LOCKED_HELP') }}
      </p>

      <div class="flex-none border-b border-n-weak px-6 py-3">
        <TabBar
          :tabs="tabItems"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>
    </template>

    <div
      v-if="isLoading"
      data-testid="kanban-board-form-loading"
      class="flex flex-1 items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD_EDIT.LOADING') }}
    </div>

    <template v-else-if="isTemplatePickerVisible">
      <p
        v-if="loadError"
        data-testid="kanban-board-template-picker-error"
        class="flex-none border-b border-n-weak bg-n-amber-2 px-6 py-2 text-sm text-n-amber-11"
      >
        {{ loadError }}
      </p>
      <div class="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <KanbanBoardTemplatePicker
          :templates="templates"
          :is-creating="isCreatingTemplate"
          @select="ensureDraftBoard"
        />
      </div>
    </template>

    <div
      v-else-if="loadError || !isAdmin"
      data-testid="kanban-board-form-error"
      class="p-6 text-sm text-n-ruby-11"
    >
      {{ loadError || t('KANBAN.BOARD_EDIT.ACCESS_DENIED') }}
    </div>

    <div v-else class="min-h-0 flex-1 overflow-y-auto">
      <section
        v-show="activeTabKey === 'stages'"
        data-testid="kanban-board-form-stages-tab"
        class="grid gap-6 p-6 lg:grid-cols-2"
      >
        <p class="text-xs text-n-slate-10 lg:col-span-2">
          {{ t('KANBAN.BOARD_EDIT.AUTOSAVE_NOTE') }}
        </p>
        <div class="grid gap-4">
          <label
            class="flex items-center justify-between gap-3 text-sm font-medium text-n-slate-12"
          >
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.ACTIVE_STATUS') }}
            <Switch v-model="form.active" @change="onActiveToggle" />
          </label>

          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.NAME') }}
            <input
              v-model="form.name"
              data-testid="kanban-board-form-name"
              type="text"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            />
          </label>

          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.DESCRIPTION') }}
            <textarea
              v-model="form.description"
              data-testid="kanban-board-form-description"
              rows="3"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            />
          </label>

          <div class="grid gap-2 border-t border-n-weak pt-4">
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.AGENTS_TITLE') }}
            </h2>
            <AgentTagInput
              :model-value="form.visibleUserIds"
              data-testid="kanban-board-form-agent-picker"
              :placeholder="
                t('KANBAN.BOARD_EDIT.STAGES_TAB.AGENTS_SEARCH_PLACEHOLDER')
              "
              :auto-open-dropdown="false"
              @update:model-value="onVisibleUserIdsChange"
            />
          </div>

          <div class="grid gap-3 border-t border-n-weak pt-4">
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.INBOXES_TITLE') }}
            </h2>
            <div class="flex flex-wrap gap-2">
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  v-model="form.inboxScopeMode"
                  type="radio"
                  value="all_inboxes"
                />
                {{ t('KANBAN.SETTINGS.INBOXES.ALL') }}
              </label>
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  v-model="form.inboxScopeMode"
                  type="radio"
                  value="selected_inboxes"
                />
                {{ t('KANBAN.SETTINGS.INBOXES.SELECTED') }}
              </label>
            </div>
            <TagMultiSelectComboBox
              v-if="form.inboxScopeMode === 'selected_inboxes'"
              v-model="form.allowedInboxIds"
              data-testid="kanban-board-form-inbox-select"
              :options="inboxOptions"
              :placeholder="t('KANBAN.SETTINGS.INBOXES.PLACEHOLDER')"
              :search-placeholder="t('KANBAN.SETTINGS.INBOXES.SEARCH')"
              :empty-state="t('KANBAN.SETTINGS.INBOXES.EMPTY')"
            />
          </div>
        </div>

        <div
          class="grid content-start gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGES_PANEL_TITLE') }}
            </h2>
          </div>

          <div
            v-if="!form.wonStageId || !form.lostStageId"
            class="grid gap-2 sm:grid-cols-2"
          >
            <label class="grid gap-1 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.WON_STAGE') }}
              <Select
                :model-value="form.wonStageId ?? ''"
                data-testid="kanban-board-form-won-stage"
                :options="wonStageOptions"
                full-width
                class="font-normal"
                @update:model-value="onWonStageChange"
              />
            </label>
            <label class="grid gap-1 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.LOST_STAGE') }}
              <Select
                :model-value="form.lostStageId ?? ''"
                data-testid="kanban-board-form-lost-stage"
                :options="lostStageOptions"
                full-width
                class="font-normal"
                @update:model-value="onLostStageChange"
              />
            </label>
          </div>
          <p
            v-else
            class="rounded-md bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-11"
          >
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.TERMINAL_STAGES_HINT') }}
          </p>

          <p v-if="hasStageSelectionConflict" class="text-sm text-n-ruby-11">
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_SELECTION_CONFLICT') }}
          </p>

          <p
            v-if="stageReconcileWarning"
            data-testid="kanban-board-form-stage-reconcile-warning"
            class="text-sm text-n-amber-11"
          >
            {{ stageReconcileWarning }}
          </p>

          <div
            v-if="showCreateStageForm"
            data-testid="kanban-board-form-create-stage-panel"
            class="grid gap-3 rounded-md border border-n-weak bg-n-surface-1 p-3"
          >
            <div class="flex min-w-0 items-center gap-3">
              <ColorPicker
                v-model="newStageColor"
                data-testid="kanban-board-form-new-stage-color"
                class="flex-none"
              />
              <input
                v-model="newStageName"
                data-testid="kanban-board-form-new-stage-name"
                type="text"
                class="reset-base !mb-0 h-10 min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
              />
              <label
                class="grid w-32 flex-none gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.SLA_HOURS') }}
                <input
                  v-model="newStageSlaHours"
                  data-testid="kanban-board-form-new-stage-sla-hours"
                  type="number"
                  min="1"
                  step="1"
                  class="reset-base !mb-0 h-10 rounded-md border border-n-weak bg-n-surface-1 px-3 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                  :placeholder="
                    t('KANBAN.BOARD_EDIT.STAGES_TAB.SLA_HOURS_PLACEHOLDER')
                  "
                />
              </label>
            </div>
            <textarea
              v-model="newStageDescription"
              data-testid="kanban-board-form-new-stage-description"
              rows="2"
              class="!mb-0 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="
                t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_DESCRIPTION_PLACEHOLDER')
              "
            />
            <div class="flex flex-wrap items-center gap-2">
              <Button
                type="button"
                data-testid="kanban-board-form-create-stage"
                icon="i-lucide-check"
                :label="t('KANBAN.ACTIONS.CREATE_STAGE_CONFIRM')"
                color="blue"
                size="sm"
                :disabled="!newStageName.trim()"
                :is-loading="isCreatingStage"
                @click="createStage"
              />
              <Button
                type="button"
                icon="i-lucide-x"
                :label="t('KANBAN.ACTIONS.CANCEL')"
                color="slate"
                size="sm"
                @click="closeCreateStageForm"
              />
            </div>
          </div>

          <p
            v-if="stageError"
            data-testid="kanban-board-form-stage-error"
            class="text-sm text-n-ruby-11"
          >
            {{ stageError }}
          </p>

          <div class="grid gap-1">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.ACTIVE_STAGES_TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-10">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.ACTIVE_STAGES_SUBTITLE') }}
            </p>
          </div>
          <p
            v-if="regularStages.length === 0"
            data-testid="kanban-board-form-empty-stages"
            class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
          >
            {{ t('KANBAN.EMPTY_STAGES') }}
          </p>

          <Draggable
            v-else
            v-model="stageListModel"
            item-key="id"
            data-testid="kanban-board-form-stage-list"
            class="grid gap-2"
            handle=".stage-drag-handle"
            ghost-class="opacity-60"
            chosen-class="opacity-90"
            :animation="180"
            @end="onStageDragEnd"
          >
            <template #item="{ element: stage }">
              <div :data-stage-id="stage.id" class="grid gap-2">
                <div
                  v-if="editingStageId !== stage.id"
                  data-testid="kanban-board-form-stage-row"
                  class="stage-drag-handle grid cursor-grab gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2"
                >
                  <div class="flex items-center gap-3">
                    <span
                      class="i-lucide-grip-vertical size-4 text-n-slate-10"
                    />
                    <div class="flex min-w-0 flex-1 items-center gap-2">
                      <span
                        class="size-4 flex-none rounded-full"
                        :style="{ backgroundColor: stage.color }"
                      />
                      <span class="min-w-0 truncate text-sm text-n-slate-12">
                        {{ stage.name }}
                      </span>
                      <span
                        data-testid="kanban-board-form-stage-card-count"
                        class="flex-none rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                      >
                        {{ getStageCardsCount(stage) }}
                      </span>
                    </div>
                    <div class="flex flex-none items-center gap-1">
                      <Button
                        data-testid="kanban-board-form-edit-stage"
                        icon="i-lucide-pencil"
                        variant="ghost"
                        color="slate"
                        size="sm"
                        :title="t('KANBAN.ACTIONS.EDIT_STAGE')"
                        @click="openEditStage(stage)"
                      />
                      <Button
                        data-testid="kanban-board-form-remove-stage"
                        icon="i-lucide-trash"
                        variant="ghost"
                        color="ruby"
                        size="sm"
                        :title="t('KANBAN.ACTIONS.REMOVE_STAGE')"
                        @click="openRemoveStageConfirmation(stage)"
                      />
                    </div>
                  </div>
                  <p
                    v-if="stage.description"
                    class="ml-7 truncate text-xs text-n-slate-11"
                  >
                    {{ stage.description }}
                  </p>
                </div>

                <KanbanStageEditPanel
                  v-else
                  v-model:name="editStageName"
                  v-model:description="editStageDescription"
                  v-model:color="editStageColor"
                  v-model:sla-hours="editStageSlaHours"
                  show-color-picker
                  show-sla-hours
                  :is-updating="isUpdatingStage"
                  @save="updateStage(stage)"
                  @cancel="closeEditStage"
                />
              </div>
            </template>
          </Draggable>
          <Button
            v-if="!showCreateStageForm"
            data-testid="kanban-board-form-create-stage-toggle"
            icon="i-lucide-plus"
            :label="t('KANBAN.ACTIONS.CREATE_STAGE')"
            color="slate"
            size="sm"
            class="w-full border border-dashed border-n-weak"
            @click="openCreateStageForm"
          />

          <div
            v-if="terminalStages.length"
            class="grid gap-3 border-t border-n-weak pt-4"
          >
            <div class="grid gap-1">
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.TERMINAL_STAGES_TITLE') }}
              </h3>
              <p class="text-xs text-n-slate-10">
                {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.TERMINAL_STAGES_SUBTITLE') }}
              </p>
            </div>

            <div
              v-for="stage in terminalStages"
              :key="stage.id"
              :data-stage-id="stage.id"
              class="grid gap-2"
            >
              <div
                v-if="editingStageId !== stage.id"
                data-testid="kanban-board-form-stage-row"
                class="grid gap-2 rounded-md border px-3 py-2"
                :class="terminalStageClasses(stage).panel"
              >
                <div class="flex items-center gap-3">
                  <span
                    class="size-4 flex-none rounded-full"
                    :class="terminalStageClasses(stage).dot"
                  />
                  <div class="flex min-w-0 flex-1 items-center gap-2">
                    <span
                      class="min-w-0 truncate text-sm font-medium"
                      :class="terminalStageClasses(stage).label"
                    >
                      {{ stage.name }}
                    </span>
                    <span
                      data-testid="kanban-board-form-stage-card-count"
                      class="flex-none rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                    >
                      {{ getStageCardsCount(stage) }}
                    </span>
                  </div>
                  <Button
                    data-testid="kanban-board-form-edit-stage"
                    icon="i-lucide-pencil"
                    variant="ghost"
                    color="slate"
                    size="sm"
                    :title="t('KANBAN.ACTIONS.EDIT_STAGE')"
                    @click="openEditStage(stage)"
                  />
                </div>
                <p
                  v-if="stage.description"
                  class="truncate text-xs text-n-slate-11"
                >
                  {{ stage.description }}
                </p>
              </div>

              <KanbanStageEditPanel
                v-else
                v-model:name="editStageName"
                v-model:description="editStageDescription"
                :panel-class="terminalStageClasses(stage).panel"
                :is-updating="isUpdatingStage"
                @save="updateStage(stage)"
                @cancel="closeEditStage"
              />
            </div>
          </div>
        </div>
      </section>

      <section
        v-show="activeTabKey === 'custom_fields'"
        data-testid="kanban-board-form-custom-fields-tab"
        class="mx-auto grid w-full max-w-2xl gap-6 p-6"
      >
        <KanbanCustomFieldsTab v-if="boardId" :board-id="boardId" />
      </section>

      <section
        v-show="activeTabKey === 'settings'"
        data-testid="kanban-board-form-settings-tab"
        class="grid gap-6 p-6 lg:w-3/4 xl:w-1/2"
      >
        <label
          class="flex items-center justify-between gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm font-medium text-n-slate-12"
        >
          {{ t('KANBAN.BOARD_EDIT.SETTINGS_TAB.LOST_REASON_REQUIRED') }}
          <input
            v-model="form.lostReasonRequired"
            type="checkbox"
            class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
          />
        </label>

        <section class="grid gap-4 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.TITLE') }}
          </h2>
          <label
            class="flex items-start gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              :checked="form.autoCreateCardsFromConversations"
              data-testid="kanban-board-form-auto-create"
              class="mt-1 size-4 rounded border-n-weak text-n-brand focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="isSavingAutomation"
              @change="onAutoCreateChange($event.target.checked)"
            />
            <span class="font-medium">
              {{ t('KANBAN.BOARD_EDIT.SETTINGS_TAB.AUTOMATIONS_TITLE') }}
            </span>
          </label>

          <div
            class="grid gap-3 rounded-md border border-n-weak bg-n-surface-2 p-3"
          >
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.TITLE') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.DESCRIPTION') }}
            </p>

            <label
              class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
            >
              {{ t('KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.WON_ENABLED') }}
              <input
                v-model="form.wonRecurrenceEnabled"
                type="checkbox"
                data-testid="kanban-board-form-won-recurrence-enabled"
                class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
              />
            </label>
            <label
              v-if="form.wonRecurrenceEnabled"
              class="grid gap-1 text-sm font-medium text-n-slate-12"
            >
              {{
                t(
                  'KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.WON_WINDOW_HOURS_LABEL'
                )
              }}
              <input
                :value="form.wonRecurrenceWindowHours"
                type="number"
                min="1"
                data-testid="kanban-board-form-won-recurrence-window-hours"
                class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                :placeholder="
                  t(
                    'KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.WINDOW_HOURS_PLACEHOLDER'
                  )
                "
                @change="onWonRecurrenceWindowHoursChange($event.target.value)"
              />
            </label>

            <label
              class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
            >
              {{ t('KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.LOST_ENABLED') }}
              <input
                v-model="form.lostRecurrenceEnabled"
                type="checkbox"
                data-testid="kanban-board-form-lost-recurrence-enabled"
                class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
              />
            </label>
            <label
              v-if="form.lostRecurrenceEnabled"
              class="grid gap-1 text-sm font-medium text-n-slate-12"
            >
              {{
                t(
                  'KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.LOST_WINDOW_HOURS_LABEL'
                )
              }}
              <input
                :value="form.lostRecurrenceWindowHours"
                type="number"
                min="1"
                data-testid="kanban-board-form-lost-recurrence-window-hours"
                class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                :placeholder="
                  t(
                    'KANBAN.SETTINGS.AUTOMATIONS.RECURRENCE.WINDOW_HOURS_PLACEHOLDER'
                  )
                "
                @change="onLostRecurrenceWindowHoursChange($event.target.value)"
              />
            </label>
          </div>
        </section>

        <section class="grid gap-3">
          <h2 class="text-base font-medium text-n-ruby-11">
            {{ t('KANBAN.BOARD_EDIT.SETTINGS_TAB.DANGER_ZONE_TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.BOARD_EDIT.SETTINGS_TAB.DANGER_ZONE_DESCRIPTION') }}
          </p>
          <Button
            data-testid="kanban-board-form-delete"
            icon="i-lucide-trash"
            :label="t('KANBAN.BOARD_EDIT.SETTINGS_TAB.DELETE_FUNNEL')"
            color="ruby"
            size="sm"
            class="w-fit"
            :is-loading="isDeleting"
            @click="openDeleteConfirmation"
          />
        </section>
      </section>

      <section
        v-show="activeTabKey === 'reasons'"
        data-testid="kanban-board-form-reasons-tab"
      >
        <KanbanReasonsTab v-if="boardId" :board-id="boardId" />
      </section>
    </div>

    <woot-delete-modal
      v-model:show="showDeleteConfirmation"
      :on-close="closeDeleteConfirmation"
      :on-confirm="deleteBoard"
      :title="t('KANBAN.REMOVE_BOARD.TITLE')"
      :message="t('KANBAN.REMOVE_BOARD.MESSAGE')"
      :confirm-text="t('KANBAN.REMOVE_BOARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_BOARD.CANCEL')"
    />

    <woot-delete-modal
      v-model:show="showRemoveStageConfirmation"
      :on-close="closeRemoveStageConfirmation"
      :on-confirm="removeStage"
      :title="t('KANBAN.REMOVE_STAGE.TITLE')"
      :message="t('KANBAN.REMOVE_STAGE.MESSAGE')"
      :confirm-text="t('KANBAN.REMOVE_STAGE.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_STAGE.CANCEL')"
    />

    <woot-delete-modal
      v-model:show="showDiscardSettingsConfirmation"
      :on-close="() => (showDiscardSettingsConfirmation = false)"
      :on-confirm="discardSettings"
      :title="t('KANBAN.BOARD_EDIT.DISCARD_CONFIRM_TITLE')"
      :message="t('KANBAN.BOARD_EDIT.DISCARD_CONFIRM_MESSAGE')"
      :confirm-text="t('KANBAN.BOARD_EDIT.DISCARD')"
      :reject-text="t('KANBAN.ACTIONS.CANCEL')"
    />

    <woot-modal
      :show="showUnsavedChangesModal"
      :show-close-button="false"
      size="modal-narrow"
      :on-close="keepEditing"
    >
      <div class="p-6" data-testid="kanban-board-form-unsaved-changes-modal">
        <h2 class="mb-2 text-base font-semibold text-n-slate-12">
          {{ t('KANBAN.BOARD_EDIT.UNSAVED_TITLE') }}
        </h2>
        <p class="mb-6 text-sm text-n-slate-11">
          {{ t('KANBAN.BOARD_EDIT.UNSAVED_MESSAGE') }}
        </p>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            color="slate"
            size="sm"
            :label="t('KANBAN.BOARD_EDIT.KEEP_EDITING')"
            @click="keepEditing"
          />
          <Button
            type="button"
            color="ruby"
            size="sm"
            :label="t('KANBAN.BOARD_EDIT.DISCARD_AND_EXIT')"
            @click="discardChangesAndExit"
          />
          <Button
            type="button"
            data-testid="kanban-board-form-save-and-exit"
            color="blue"
            size="sm"
            :label="t('KANBAN.BOARD_EDIT.SAVE_AND_EXIT')"
            :disabled="saveDisabled"
            :is-loading="isSavingSettings"
            @click="saveAndExit"
          />
        </div>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDiscardDraftModal"
      :on-close="keepEditing"
      :on-confirm="discardDraft"
      :is-loading="isDiscarding"
      :title="t('KANBAN.BOARD_EDIT.DISCARD_DRAFT_TITLE')"
      :message="t('KANBAN.BOARD_EDIT.DISCARD_DRAFT_MESSAGE')"
      :confirm-text="t('KANBAN.BOARD_EDIT.DISCARD_DRAFT_CONFIRM')"
      :reject-text="t('KANBAN.BOARD_EDIT.KEEP_EDITING')"
    />

    <woot-modal
      v-model:show="showImportExistingConversationsModal"
      :on-close="closeImportExistingConversationsModal"
      :show-close-button="false"
    >
      <div
        class="flex w-full flex-col gap-4 rounded-lg bg-n-surface-1 p-6 text-n-slate-12"
        data-testid="kanban-board-form-import-existing-conversations-modal"
      >
        <div class="grid gap-1">
          <h3 class="text-lg font-medium">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.IMPORT_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.IMPORT_DESCRIPTION') }}
          </p>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            v-model="ignoreGroupsForImport"
            data-testid="kanban-board-form-import-ignore-groups"
            type="checkbox"
            class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
          />
          {{ t('KANBAN.SETTINGS.AUTOMATIONS.IGNORE_GROUPS') }}
        </label>

        <p
          v-if="importError"
          data-testid="kanban-board-form-import-error"
          class="text-sm text-n-ruby-11"
        >
          {{ importError }}
        </p>

        <div class="flex justify-end gap-2">
          <Button
            type="button"
            data-testid="kanban-board-form-import-skip"
            :label="t('KANBAN.SETTINGS.AUTOMATIONS.SKIP_IMPORT')"
            color="slate"
            size="sm"
            :disabled="isImportingConversations"
            @click="closeImportExistingConversationsModal"
          />
          <Button
            type="button"
            data-testid="kanban-board-form-import-existing-conversations"
            icon="i-lucide-upload"
            :label="t('KANBAN.SETTINGS.AUTOMATIONS.IMPORT_EXISTING')"
            color="blue"
            size="sm"
            :is-loading="isImportingConversations"
            @click="importExistingConversations"
          />
        </div>
      </div>
    </woot-modal>
  </main>
</template>
