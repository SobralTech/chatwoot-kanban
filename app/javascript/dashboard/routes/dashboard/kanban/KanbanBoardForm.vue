<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import {
  DEFAULT_KANBAN_STAGE_COLOR,
  KANBAN_STAGE_COLOR_OPTIONS,
  getKanbanStageColorOption,
} from 'dashboard/helper/kanbanStageColors';
import KanbanCustomFieldsTab from './KanbanCustomFieldsTab.vue';
import KanbanReasonsTab from './KanbanReasonsTab.vue';

const TAB_KEYS = ['stages', 'custom_fields', 'settings', 'reasons'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const { isAdmin } = useAdmin();

const boardId = ref(route.params.boardId ? Number(route.params.boardId) : null);

const isLoading = ref(true);
const isActivating = ref(false);
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

const stages = ref([]);
const newStageName = ref('');
const newStageDescription = ref('');
const newStageColor = ref(DEFAULT_KANBAN_STAGE_COLOR);
const editingStageId = ref(null);
const editStageName = ref('');
const editStageDescription = ref('');
const editStageColor = ref(DEFAULT_KANBAN_STAGE_COLOR);
const stagePendingRemoval = ref(null);
const ignoreGroupsForImport = ref(false);

const agentSearchQuery = ref('');
const activeTabIndex = ref(0);

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

const stageListModel = computed({
  get: () => stages.value,
  set: nextStages => {
    stages.value = nextStages;
  },
});
const wonStageOptions = computed(() =>
  stages.value.filter(stage => stage.id !== form.lostStageId)
);
const lostStageOptions = computed(() =>
  stages.value.filter(stage => stage.id !== form.wonStageId)
);
const hasStageSelectionConflict = computed(
  () =>
    form.wonStageId && form.lostStageId && form.wonStageId === form.lostStageId
);
const { canMoveStage } = useKanbanStageOrder({
  stages,
  wonStageId: computed(() => form.wonStageId),
  lostStageId: computed(() => form.lostStageId),
});

const tabItems = computed(() => [
  { label: t('KANBAN.BOARD_EDIT.TABS.STAGES') },
  { label: t('KANBAN.BOARD_EDIT.TABS.CUSTOM_FIELDS') },
  { label: t('KANBAN.BOARD_EDIT.TABS.SETTINGS') },
  { label: t('KANBAN.BOARD_EDIT.TABS.REASONS') },
]);
const activeTabKey = computed(() => TAB_KEYS[activeTabIndex.value]);

const pageTitle = computed(() =>
  form.active
    ? t('KANBAN.BOARD_EDIT.EDIT_TITLE', { name: form.name })
    : t('KANBAN.BOARD_EDIT.CREATE_TITLE')
);

const canActivate = computed(() => !!(form.wonStageId && form.lostStageId));
const saveDisabled = computed(
  () =>
    isLoading.value ||
    !!loadError.value ||
    isActivating.value ||
    (!form.active && !canActivate.value)
);

const discardDisabled = computed(() => isLoading.value || !!loadError.value);

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }))
);

const filteredAgentResults = computed(() => {
  const query = agentSearchQuery.value.trim().toLowerCase();

  return agents.value.filter(agent => {
    if (form.visibleUserIds.includes(agent.id)) return false;
    if (!query) return true;

    const name = (agent.name || '').toLowerCase();
    const email = (agent.email || '').toLowerCase();
    return name.includes(query) || email.includes(query);
  });
});

const selectedAgents = computed(() =>
  form.visibleUserIds
    .map(id => agents.value.find(agent => agent.id === id))
    .filter(Boolean)
);

const getErrorMessage = (error, fallbackMessage) =>
  error?.response?.data?.error ||
  error?.response?.data?.message ||
  error?.message ||
  fallbackMessage;

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
  form.wonStageId = settings.wonStageId || null;
  form.lostStageId = settings.lostStageId || null;
  form.lostReasonRequired = settings.lostReasonRequired || false;
  form.wonRecurrenceEnabled = settings.wonRecurrenceEnabled || false;
  form.wonRecurrenceWindowHours = settings.wonRecurrenceWindowHours ?? null;
  form.lostRecurrenceEnabled = settings.lostRecurrenceEnabled || false;
  form.lostRecurrenceWindowHours = settings.lostRecurrenceWindowHours ?? null;
};

const applyBoard = payload => {
  const board = camelcaseKeys(payload || {}, { deep: true });
  stages.value = board.stages || [];
};

const refreshBoard = async () => {
  const response = await KanbanBoardsAPI.showBoard(boardId.value);
  applyBoard(response.data);
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
  } catch (error) {
    loadError.value = getErrorMessage(error, t('KANBAN.BOARD_EDIT.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const ensureDraftBoard = async () => {
  if (route.name !== 'kanban_board_create_form') return;

  try {
    await store.dispatch('kanbanBoards/fetchBoards');
    const position = store.getters['kanbanBoards/kanbanBoards'].length;
    const response = await KanbanBoardsAPI.create({
      kanban_board: {
        name: t('KANBAN.BOARD_EDIT.NEW_BOARD_DEFAULT_NAME'),
        active: false,
        position,
      },
    });
    const created = camelcaseKeys(response.data || {}, { deep: true });
    boardId.value = created.id;

    await router.replace({
      name: 'kanban_board_edit_form',
      params: {
        accountId: route.params.accountId,
        boardId: boardId.value,
      },
    });
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.BOARD_EDIT.CREATE_ERROR')
    );
  }
};

const buildSettingsPayload = () => ({
  kanban_board: {
    name: form.name.trim(),
    description: form.description.trim(),
    auto_create_cards_from_conversations: form.autoCreateCardsFromConversations,
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
  if (!form.name.trim() || isSavingSettings.value || !isAdmin.value) return;

  isSavingSettings.value = true;

  try {
    const response = await KanbanBoardsAPI.updateSettings(
      boardId.value,
      buildSettingsPayload()
    );
    applySettings(response.data);
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
  } catch (error) {
    useAlert(getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR')));
  } finally {
    isSavingSettings.value = false;
  }
};

const setInboxScopeMode = mode => {
  form.inboxScopeMode = mode;
  persistSettings();
};

const onAllowedInboxIdsChange = value => {
  form.allowedInboxIds = value;
  persistSettings();
};

const setVisibilityFromSelection = () => {
  form.visibilityMode = form.visibleUserIds.length
    ? 'selected_agents'
    : 'all_agents';
};

const addAgent = agent => {
  if (form.visibleUserIds.includes(agent.id)) return;

  form.visibleUserIds = [...form.visibleUserIds, agent.id];
  setVisibilityFromSelection();
  persistSettings();
};

const removeAgent = agent => {
  form.visibleUserIds = form.visibleUserIds.filter(id => id !== agent.id);
  setVisibilityFromSelection();
  persistSettings();
};

const clearAgentSelection = () => {
  if (!form.visibleUserIds.length) return;

  form.visibleUserIds = [];
  setVisibilityFromSelection();
  persistSettings();
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
  persistSettings();
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
  persistSettings();
};

const onLostReasonRequiredChange = checked => {
  form.lostReasonRequired = checked;
  persistSettings();
};

const onWonRecurrenceEnabledChange = checked => {
  form.wonRecurrenceEnabled = checked;
  persistSettings();
};

const onWonRecurrenceWindowHoursChange = value => {
  form.wonRecurrenceWindowHours = value === '' ? null : Number(value);
  persistSettings();
};

const onLostRecurrenceEnabledChange = checked => {
  form.lostRecurrenceEnabled = checked;
  persistSettings();
};

const onLostRecurrenceWindowHoursChange = value => {
  form.lostRecurrenceWindowHours = value === '' ? null : Number(value);
  persistSettings();
};

const onAutoCreateChange = async checked => {
  if (isSavingAutomation.value || !isAdmin.value) return;

  form.autoCreateCardsFromConversations = checked;
  isSavingAutomation.value = true;

  try {
    const response = await KanbanBoardsAPI.updateSettings(
      boardId.value,
      buildSettingsPayload()
    );
    applySettings(response.data);
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

const getStageColorClass = stage =>
  getKanbanStageColorOption(stage.color).swatchClass;

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
};

const createStage = async () => {
  const name = newStageName.value.trim();
  if (!name || isCreatingStage.value || !isAdmin.value) return;

  isCreatingStage.value = true;
  stageError.value = '';

  try {
    await KanbanBoardsAPI.createStage(boardId.value, {
      stage: {
        name,
        description: newStageDescription.value.trim(),
        color: newStageColor.value,
        position: stages.value.length + 1,
      },
    });
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
  editStageColor.value = stage.color || DEFAULT_KANBAN_STAGE_COLOR;
};

const closeEditStage = () => {
  editingStageId.value = null;
  editStageName.value = '';
  editStageDescription.value = '';
  editStageColor.value = DEFAULT_KANBAN_STAGE_COLOR;
};

const updateStage = async stage => {
  const name = editStageName.value.trim();
  if (!name || isUpdatingStage.value || !isAdmin.value) return;

  isUpdatingStage.value = true;
  stageError.value = '';

  try {
    await KanbanBoardsAPI.updateStage(boardId.value, stage.id, {
      stage: {
        name,
        description: editStageDescription.value.trim(),
        color: editStageColor.value,
      },
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
    if (form.wonStageId === stage.id) form.wonStageId = null;
    if (form.lostStageId === stage.id) form.lostStageId = null;
    await refreshBoard();
    await store.dispatch('kanbanBoards/refreshBoards');
    useAlert(t('KANBAN.ACTIONS.REMOVE_STAGE_SUCCESS'));
  } catch (error) {
    stageError.value =
      error?.response?.status === 422
        ? t('KANBAN.ACTIONS.REMOVE_STAGE_NOT_EMPTY')
        : getErrorMessage(error, t('KANBAN.ACTIONS.REMOVE_STAGE_ERROR'));
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

const goToBoard = () => {
  router.push({
    name: 'kanban_board_show',
    params: { accountId: route.params.accountId, boardId: boardId.value },
  });
};

const onSave = async () => {
  if (form.active) {
    goToBoard();
    return;
  }

  if (!canActivate.value || isActivating.value) return;

  isActivating.value = true;

  try {
    const response = await KanbanBoardsAPI.update(boardId.value, {
      kanban_board: { active: true },
    });
    form.active = camelcaseKeys(response.data || {}, { deep: true }).active;
    await store.dispatch('kanbanBoards/refreshBoards');
    goToBoard();
  } catch (error) {
    if (error?.response?.status === 422) {
      useAlert(t('KANBAN.BOARD_EDIT.ACTIVATE_ERROR'));
    } else {
      useAlert(getErrorMessage(error, t('KANBAN.BOARD_EDIT.ACTIVATE_ERROR')));
    }
  } finally {
    isActivating.value = false;
  }
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

const onDiscard = async () => {
  if (isDiscarding.value || !boardId.value) return;

  if (form.active) {
    goToBoard();
    return;
  }

  isDiscarding.value = true;

  try {
    await KanbanBoardsAPI.delete(boardId.value);
    await store.dispatch('kanbanBoards/refreshBoards');
    router.push({
      name: 'kanban_boards',
      params: { accountId: route.params.accountId },
    });
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

onMounted(async () => {
  await ensureDraftBoard();

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
      <h1 class="min-w-0 truncate text-lg font-medium text-n-slate-12">
        {{ pageTitle }}
      </h1>
      <div class="flex flex-none items-center gap-2">
        <Button
          data-testid="kanban-board-form-discard"
          icon="i-lucide-x"
          variant="outline"
          color="slate"
          size="sm"
          :label="t('KANBAN.BOARD_EDIT.DISCARD')"
          :disabled="discardDisabled"
          :is-loading="isDiscarding"
          @click="onDiscard"
        />
        <Button
          data-testid="kanban-board-form-save"
          icon="i-lucide-check"
          color="blue"
          size="sm"
          :label="t('KANBAN.BOARD_EDIT.SAVE')"
          :disabled="saveDisabled"
          :is-loading="isActivating"
          @click="onSave"
        />
      </div>
    </header>

    <p
      v-if="!isLoading && !loadError && !form.active && !canActivate"
      data-testid="kanban-board-form-locked-help"
      class="flex-none border-b border-n-weak bg-n-amber-2 px-6 py-2 text-sm text-n-amber-11"
    >
      {{ t('KANBAN.BOARD_EDIT.SAVE_LOCKED_HELP') }}
    </p>

    <div class="flex-none border-b border-n-weak px-6 py-3">
      <TabBar
        :tabs="tabItems"
        :initial-active-tab="activeTabIndex"
        @tab-changed="onTabChanged"
      />
    </div>

    <div
      v-if="isLoading"
      data-testid="kanban-board-form-loading"
      class="flex flex-1 items-center justify-center text-sm text-n-slate-11"
    >
      {{ t('KANBAN.BOARD_EDIT.LOADING') }}
    </div>

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
              @blur="persistSettings"
            />
          </label>

          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.DESCRIPTION') }}
            <textarea
              v-model="form.description"
              data-testid="kanban-board-form-description"
              rows="3"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              @blur="persistSettings"
            />
          </label>

          <div class="grid gap-2 border-t border-n-weak pt-4">
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.AGENTS_TITLE') }}
            </h2>
            <input
              v-model="agentSearchQuery"
              data-testid="kanban-board-form-agent-search"
              type="text"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="
                t('KANBAN.BOARD_EDIT.STAGES_TAB.AGENTS_SEARCH_PLACEHOLDER')
              "
            />
            <div
              v-if="filteredAgentResults.length"
              class="grid max-h-40 gap-1 overflow-y-auto rounded-md border border-n-weak bg-n-surface-2 p-1"
            >
              <button
                v-for="agent in filteredAgentResults"
                :key="agent.id"
                type="button"
                data-testid="kanban-board-form-agent-option"
                class="flex items-center justify-between rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="addAgent(agent)"
              >
                <span class="min-w-0 truncate">{{
                  agent.name || agent.email
                }}</span>
                <i class="i-lucide-plus size-4 flex-none text-n-slate-10" />
              </button>
            </div>
            <p v-else class="text-sm text-n-slate-11">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.AGENTS_EMPTY') }}
            </p>

            <div
              v-if="selectedAgents.length"
              data-testid="kanban-board-form-selected-agents"
              class="flex flex-wrap gap-2"
            >
              <span
                v-for="agent in selectedAgents"
                :key="agent.id"
                class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
              >
                {{ agent.name || agent.email }}
                <button
                  type="button"
                  :aria-label="
                    t('KANBAN.BOARD_EDIT.STAGES_TAB.REMOVE_AGENT', {
                      name: agent.name || agent.email,
                    })
                  "
                  @click="removeAgent(agent)"
                >
                  <i class="i-lucide-x size-3" />
                </button>
              </span>
            </div>
            <Button
              v-if="selectedAgents.length"
              type="button"
              data-testid="kanban-board-form-clear-agents"
              variant="link"
              color="slate"
              size="sm"
              class="w-fit"
              :label="t('KANBAN.BOARD_EDIT.STAGES_TAB.CLEAR_SELECTION')"
              @click="clearAgentSelection"
            />
          </div>

          <div class="grid gap-3 border-t border-n-weak pt-4">
            <h2 class="text-base font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.INBOXES_TITLE') }}
            </h2>
            <div class="flex flex-wrap gap-2">
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  type="radio"
                  :checked="form.inboxScopeMode === 'all_inboxes'"
                  @change="setInboxScopeMode('all_inboxes')"
                />
                {{ t('KANBAN.SETTINGS.INBOXES.ALL') }}
              </label>
              <label class="flex items-center gap-2 text-sm text-n-slate-12">
                <input
                  type="radio"
                  :checked="form.inboxScopeMode === 'selected_inboxes'"
                  @change="setInboxScopeMode('selected_inboxes')"
                />
                {{ t('KANBAN.SETTINGS.INBOXES.SELECTED') }}
              </label>
            </div>
            <TagMultiSelectComboBox
              v-if="form.inboxScopeMode === 'selected_inboxes'"
              :model-value="form.allowedInboxIds"
              data-testid="kanban-board-form-inbox-select"
              :options="inboxOptions"
              :placeholder="t('KANBAN.SETTINGS.INBOXES.PLACEHOLDER')"
              :search-placeholder="t('KANBAN.SETTINGS.INBOXES.SEARCH')"
              :empty-state="t('KANBAN.SETTINGS.INBOXES.EMPTY')"
              @update:model-value="onAllowedInboxIdsChange"
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
            <Button
              v-if="!showCreateStageForm"
              data-testid="kanban-board-form-create-stage-toggle"
              icon="i-lucide-plus"
              :label="t('KANBAN.ACTIONS.CREATE_STAGE')"
              color="slate"
              size="sm"
              @click="openCreateStageForm"
            />
          </div>

          <div class="grid gap-2 sm:grid-cols-2">
            <label class="grid gap-1 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.WON_STAGE') }}
              <select
                :value="form.wonStageId ?? ''"
                data-testid="kanban-board-form-won-stage"
                class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none focus:border-n-brand"
                @change="onWonStageChange($event.target.value)"
              >
                <option value="">
                  {{
                    t('KANBAN.BOARD_EDIT.STAGES_TAB.SELECT_STAGE_PLACEHOLDER')
                  }}
                </option>
                <option
                  v-for="stage in wonStageOptions"
                  :key="stage.id"
                  :value="stage.id"
                >
                  {{ stage.name }}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.LOST_STAGE') }}
              <select
                :value="form.lostStageId ?? ''"
                data-testid="kanban-board-form-lost-stage"
                class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none focus:border-n-brand"
                @change="onLostStageChange($event.target.value)"
              >
                <option value="">
                  {{
                    t('KANBAN.BOARD_EDIT.STAGES_TAB.SELECT_STAGE_PLACEHOLDER')
                  }}
                </option>
                <option
                  v-for="stage in lostStageOptions"
                  :key="stage.id"
                  :value="stage.id"
                >
                  {{ stage.name }}
                </option>
              </select>
            </label>
          </div>

          <p v-if="hasStageSelectionConflict" class="text-sm text-n-ruby-11">
            {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_SELECTION_CONFLICT') }}
          </p>

          <div
            v-if="showCreateStageForm"
            data-testid="kanban-board-form-create-stage-panel"
            class="grid gap-3 rounded-md border border-n-weak bg-n-surface-1 p-3"
          >
            <div class="flex flex-wrap items-center gap-2">
              <button
                v-for="colorOption in KANBAN_STAGE_COLOR_OPTIONS"
                :key="colorOption.value"
                type="button"
                class="size-5 rounded-full border border-n-strong ring-offset-2"
                :class="[
                  colorOption.swatchClass,
                  newStageColor === colorOption.value
                    ? 'ring-2 ring-n-brand'
                    : 'hover:ring-2 hover:ring-n-weak',
                ]"
                :aria-label="
                  t('KANBAN.ACTIONS.SELECT_STAGE_COLOR', {
                    color: colorOption.value,
                  })
                "
                @click="newStageColor = colorOption.value"
              />
            </div>
            <input
              v-model="newStageName"
              data-testid="kanban-board-form-new-stage-name"
              type="text"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
              :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
            />
            <textarea
              v-model="newStageDescription"
              data-testid="kanban-board-form-new-stage-description"
              rows="2"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
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

          <p
            v-if="stages.length === 0"
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
            :move="canMoveStage"
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
                        :class="getStageColorClass(stage)"
                      />
                      <span class="min-w-0 truncate text-sm text-n-slate-12">
                        {{ stage.name }}
                      </span>
                      <span
                        v-if="stage.id === form.wonStageId"
                        class="flex-none rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
                      >
                        {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.WON_TAG') }}
                      </span>
                      <span
                        v-if="stage.id === form.lostStageId"
                        class="flex-none rounded-full bg-n-ruby-3 px-2 py-0.5 text-xs font-medium text-n-ruby-11"
                      >
                        {{ t('KANBAN.BOARD_EDIT.STAGES_TAB.LOST_TAG') }}
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

                <div
                  v-else
                  data-testid="kanban-board-form-edit-stage-panel"
                  class="grid gap-3 rounded-md border border-n-weak bg-n-surface-1 p-3"
                >
                  <div class="flex flex-wrap items-center gap-2">
                    <button
                      v-for="colorOption in KANBAN_STAGE_COLOR_OPTIONS"
                      :key="colorOption.value"
                      type="button"
                      class="size-5 rounded-full border border-n-strong ring-offset-2"
                      :class="[
                        colorOption.swatchClass,
                        editStageColor === colorOption.value
                          ? 'ring-2 ring-n-brand'
                          : 'hover:ring-2 hover:ring-n-weak',
                      ]"
                      :aria-label="
                        t('KANBAN.ACTIONS.SELECT_STAGE_COLOR', {
                          color: colorOption.value,
                        })
                      "
                      @click="editStageColor = colorOption.value"
                    />
                  </div>
                  <input
                    v-model="editStageName"
                    data-testid="kanban-board-form-edit-stage-name"
                    type="text"
                    class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                    :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
                  />
                  <textarea
                    v-model="editStageDescription"
                    data-testid="kanban-board-form-edit-stage-description"
                    rows="2"
                    class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                    :placeholder="
                      t(
                        'KANBAN.BOARD_EDIT.STAGES_TAB.STAGE_DESCRIPTION_PLACEHOLDER'
                      )
                    "
                  />
                  <div class="flex flex-wrap items-center gap-2">
                    <Button
                      type="button"
                      data-testid="kanban-board-form-save-stage"
                      icon="i-lucide-check"
                      :label="t('KANBAN.ACTIONS.SAVE_STAGE')"
                      color="blue"
                      size="sm"
                      :disabled="!editStageName.trim()"
                      :is-loading="isUpdatingStage"
                      @click="updateStage(stage)"
                    />
                    <Button
                      type="button"
                      icon="i-lucide-x"
                      :label="t('KANBAN.ACTIONS.CANCEL')"
                      color="slate"
                      size="sm"
                      @click="closeEditStage"
                    />
                  </div>
                </div>
              </div>
            </template>
          </Draggable>
        </div>
      </section>

      <section
        v-show="activeTabKey === 'custom_fields'"
        data-testid="kanban-board-form-custom-fields-tab"
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
            type="checkbox"
            :checked="form.lostReasonRequired"
            class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
            @change="onLostReasonRequiredChange($event.target.checked)"
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
                type="checkbox"
                :checked="form.wonRecurrenceEnabled"
                data-testid="kanban-board-form-won-recurrence-enabled"
                class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
                @change="onWonRecurrenceEnabledChange($event.target.checked)"
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
                type="checkbox"
                :checked="form.lostRecurrenceEnabled"
                data-testid="kanban-board-form-lost-recurrence-enabled"
                class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
                @change="onLostRecurrenceEnabledChange($event.target.checked)"
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
