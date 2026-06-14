<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import Draggable from 'vuedraggable';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import {
  DEFAULT_KANBAN_STAGE_COLOR,
  KANBAN_STAGE_COLOR_OPTIONS,
  getKanbanStageColorOption,
} from 'dashboard/helper/kanbanStageColors';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const { isAdmin } = useAdmin();

const isLoading = ref(false);
const isSaving = ref(false);
const isSavingAutomation = ref(false);
const isDeleting = ref(false);
const isCreatingStage = ref(false);
const isImportingConversations = ref(false);
const loadError = ref('');
const saveError = ref('');
const stageError = ref('');
const importError = ref('');
const showDeleteConfirmation = ref(false);
const showCreateStageForm = ref(false);
const showImportExistingConversationsModal = ref(false);
const stages = ref([]);
const newStageName = ref('');
const newStageColor = ref(DEFAULT_KANBAN_STAGE_COLOR);
const activeStageActionKey = ref('');
const ignoreGroupsForImport = ref(false);

const form = reactive({
  name: '',
  description: '',
  autoCreateCardsFromConversations: false,
  visibilityMode: 'all_agents',
  visibleUserIds: [],
  inboxScopeMode: 'all_inboxes',
  allowedInboxIds: [],
});

const boardId = computed(() => Number(route.params.boardId));
const stageListModel = computed({
  get: () => stages.value,
  set: nextStages => {
    stages.value = nextStages;
  },
});

const agentOptions = computed(() =>
  agents.value.map(agent => ({
    value: agent.id,
    label: agent.name || agent.email,
  }))
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

const applySettings = payload => {
  const settings = camelcaseKeys(payload || {}, { deep: true });

  form.name = settings.name || '';
  form.description = settings.description || '';
  form.autoCreateCardsFromConversations =
    settings.autoCreateCardsFromConversations || false;
  form.visibilityMode = settings.visibilityMode || 'all_agents';
  form.visibleUserIds = settings.visibleUserIds || [];
  form.inboxScopeMode = settings.inboxScopeMode || 'all_inboxes';
  form.allowedInboxIds = settings.allowedInboxIds || [];
};

const applyBoard = payload => {
  const board = camelcaseKeys(payload || {}, { deep: true });
  stages.value = board.stages || [];
};

const fetchSettings = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const [response, boardResponse] = await Promise.all([
      KanbanBoardsAPI.getSettings(boardId.value),
      KanbanBoardsAPI.showBoard(boardId.value),
      store.dispatch('agents/get'),
      store.dispatch('inboxes/get'),
    ]);
    applySettings(response.data);
    applyBoard(boardResponse.data);
  } catch (error) {
    loadError.value = getErrorMessage(error, t('KANBAN.SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const refreshBoard = async () => {
  const response = await KanbanBoardsAPI.showBoard(boardId.value);
  applyBoard(response.data);
};

const buildPayload = () => ({
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
  },
});

const saveSettings = async () => {
  if (!form.name.trim() || isSaving.value || !isAdmin.value) return;

  isSaving.value = true;
  saveError.value = '';

  try {
    const response = await KanbanBoardsAPI.updateSettings(
      boardId.value,
      buildPayload()
    );
    applySettings(response.data);
    await store.dispatch('kanbanBoards/refreshBoards');
    useAlert(t('KANBAN.SETTINGS.SAVE_SUCCESS'));
  } catch (error) {
    saveError.value = getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR'));
    useAlert(saveError.value);
  } finally {
    isSaving.value = false;
  }
};

const saveAutomationSetting = async event => {
  const enabled = event.target.checked;
  if (isSavingAutomation.value || !isAdmin.value) return;

  isSavingAutomation.value = true;
  saveError.value = '';

  try {
    const response = await KanbanBoardsAPI.updateSettings(
      boardId.value,
      buildPayload()
    );
    applySettings(response.data);
    await store.dispatch('kanbanBoards/refreshBoards');

    if (enabled) {
      importError.value = '';
      ignoreGroupsForImport.value = false;
      showImportExistingConversationsModal.value = true;
    }
  } catch (error) {
    form.autoCreateCardsFromConversations = !enabled;
    saveError.value = getErrorMessage(error, t('KANBAN.SETTINGS.SAVE_ERROR'));
    useAlert(saveError.value);
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

const reorderStageByPosition = async (stage, position) => {
  if (!stage?.id || activeStageActionKey.value || !isAdmin.value) return;

  activeStageActionKey.value = `reorder-stage-${stage.id}`;
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
  } finally {
    activeStageActionKey.value = '';
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

const openDeleteConfirmation = () => {
  showDeleteConfirmation.value = true;
};

const closeDeleteConfirmation = () => {
  showDeleteConfirmation.value = false;
};

const deleteBoard = async () => {
  if (isDeleting.value || !isAdmin.value) return;

  isDeleting.value = true;
  saveError.value = '';

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
    saveError.value = getErrorMessage(
      error,
      t('KANBAN.ACTIONS.REMOVE_BOARD_ERROR')
    );
    useAlert(saveError.value);
  } finally {
    isDeleting.value = false;
  }
};

onMounted(fetchSettings);
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <div class="flex w-full flex-col gap-6 overflow-y-auto p-8">
      <header class="flex items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-2xl font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('KANBAN.SETTINGS.DESCRIPTION') }}
          </p>
        </div>
        <Button
          icon="i-lucide-arrow-left"
          :label="t('KANBAN.SETTINGS.BACK_TO_BOARD')"
          color="slate"
          size="sm"
          @click="
            router.push({
              name: 'kanban_board_show',
              params: { accountId: route.params.accountId, boardId },
            })
          "
        />
      </header>

      <div
        v-if="isLoading"
        data-testid="kanban-settings-loading"
        class="flex items-center justify-center py-16 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.SETTINGS.LOADING') }}
      </div>

      <div
        v-else-if="loadError || !isAdmin"
        data-testid="kanban-settings-error"
        class="rounded-lg border border-n-weak bg-n-surface-2 p-6 text-sm text-n-ruby-11"
      >
        {{ loadError || t('KANBAN.SETTINGS.ACCESS_DENIED') }}
      </div>

      <form
        v-else
        data-testid="kanban-settings-form"
        class="grid gap-6"
        @submit.prevent="saveSettings"
      >
        <section class="grid gap-4 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.GENERAL.TITLE') }}
          </h2>
          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.GENERAL.NAME') }}
            <input
              v-model="form.name"
              data-testid="kanban-settings-name"
              type="text"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            />
          </label>
          <label class="grid gap-1 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.GENERAL.DESCRIPTION') }}
            <textarea
              v-model="form.description"
              data-testid="kanban-settings-description"
              rows="3"
              class="rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
            />
          </label>

          <div class="grid gap-3">
            <div class="flex items-center justify-end">
              <Button
                v-if="!showCreateStageForm"
                data-testid="kanban-settings-create-stage-toggle"
                icon="i-lucide-plus"
                :label="t('KANBAN.ACTIONS.CREATE_STAGE')"
                color="slate"
                size="sm"
                @click="openCreateStageForm"
              />
            </div>

            <div
              v-if="showCreateStageForm"
              data-testid="kanban-settings-create-stage-panel"
              class="grid gap-3 rounded-md border border-n-weak bg-n-surface-2 p-3"
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
              <div class="flex flex-wrap items-center gap-2">
                <input
                  v-model="newStageName"
                  data-testid="kanban-settings-new-stage-name"
                  type="text"
                  class="min-w-64 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm font-normal text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
                  :placeholder="t('KANBAN.ACTIONS.STAGE_NAME_PLACEHOLDER')"
                />
                <Button
                  type="button"
                  data-testid="kanban-settings-create-stage"
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
              data-testid="kanban-settings-stage-error"
              class="text-sm text-n-ruby-11"
            >
              {{ stageError }}
            </p>

            <p
              v-if="stages.length === 0"
              data-testid="kanban-settings-empty-stages"
              class="rounded-md border border-dashed border-n-weak px-3 py-4 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.EMPTY_STAGES') }}
            </p>

            <Draggable
              v-else
              v-model="stageListModel"
              item-key="id"
              data-testid="kanban-settings-stage-list"
              class="grid gap-2"
              handle=".stage-drag-handle"
              ghost-class="opacity-60"
              chosen-class="opacity-90"
              :animation="180"
              @end="onStageDragEnd"
            >
              <template #item="{ element: stage }">
                <div
                  :data-stage-id="stage.id"
                  data-testid="kanban-settings-stage-row"
                  class="stage-drag-handle flex cursor-grab items-center gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2"
                >
                  <span class="i-lucide-grip-vertical size-4 text-n-slate-10" />
                  <span
                    class="size-4 flex-none rounded-full"
                    :class="getStageColorClass(stage)"
                  />
                  <span class="min-w-0 truncate text-sm text-n-slate-12">
                    {{ stage.name }}
                  </span>
                  <span
                    data-testid="kanban-settings-stage-card-count"
                    class="ml-auto flex-none rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                  >
                    {{ getStageCardsCount(stage) }}
                  </span>
                </div>
              </template>
            </Draggable>
          </div>
        </section>

        <section class="grid gap-4 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.AGENTS.TITLE') }}
          </h2>
          <div class="flex flex-wrap gap-2">
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="form.visibilityMode"
                data-testid="kanban-settings-all-agents"
                type="radio"
                value="all_agents"
              />
              {{ t('KANBAN.SETTINGS.AGENTS.ALL') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="form.visibilityMode"
                data-testid="kanban-settings-selected-agents"
                type="radio"
                value="selected_agents"
              />
              {{ t('KANBAN.SETTINGS.AGENTS.SELECTED') }}
            </label>
          </div>
          <TagMultiSelectComboBox
            v-if="form.visibilityMode === 'selected_agents'"
            v-model="form.visibleUserIds"
            data-testid="kanban-settings-agent-select"
            :options="agentOptions"
            :placeholder="t('KANBAN.SETTINGS.AGENTS.PLACEHOLDER')"
            :search-placeholder="t('KANBAN.SETTINGS.AGENTS.SEARCH')"
            :empty-state="t('KANBAN.SETTINGS.AGENTS.EMPTY')"
          />
        </section>

        <section class="grid gap-4 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.INBOXES.TITLE') }}
          </h2>
          <div class="flex flex-wrap gap-2">
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="form.inboxScopeMode"
                data-testid="kanban-settings-all-inboxes"
                type="radio"
                value="all_inboxes"
              />
              {{ t('KANBAN.SETTINGS.INBOXES.ALL') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="form.inboxScopeMode"
                data-testid="kanban-settings-selected-inboxes"
                type="radio"
                value="selected_inboxes"
              />
              {{ t('KANBAN.SETTINGS.INBOXES.SELECTED') }}
            </label>
          </div>
          <TagMultiSelectComboBox
            v-if="form.inboxScopeMode === 'selected_inboxes'"
            v-model="form.allowedInboxIds"
            data-testid="kanban-settings-inbox-select"
            :options="inboxOptions"
            :placeholder="t('KANBAN.SETTINGS.INBOXES.PLACEHOLDER')"
            :search-placeholder="t('KANBAN.SETTINGS.INBOXES.SEARCH')"
            :empty-state="t('KANBAN.SETTINGS.INBOXES.EMPTY')"
          />
        </section>

        <section class="grid gap-4 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.TITLE') }}
          </h2>
          <label
            class="flex items-start gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12"
          >
            <input
              v-model="form.autoCreateCardsFromConversations"
              data-testid="kanban-settings-auto-create"
              type="checkbox"
              class="mt-1 size-4 rounded border-n-weak text-n-brand focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="isSavingAutomation"
              @change="saveAutomationSetting"
            />
            <span class="font-medium">
              {{ t('KANBAN.SETTINGS.AUTOMATIONS.AUTO_CREATE') }}
            </span>
          </label>
        </section>

        <section class="grid gap-3 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-ruby-11">
            {{ t('KANBAN.SETTINGS.DELETE.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.SETTINGS.DELETE.DESCRIPTION') }}
          </p>
          <Button
            data-testid="kanban-settings-delete"
            icon="i-lucide-trash"
            :label="t('KANBAN.SETTINGS.DELETE.ACTION')"
            color="ruby"
            size="sm"
            class="w-fit"
            :is-loading="isDeleting"
            @click="openDeleteConfirmation"
          />
        </section>

        <p
          v-if="saveError"
          data-testid="kanban-settings-save-error"
          class="text-sm text-n-ruby-11"
        >
          {{ saveError }}
        </p>

        <div class="flex justify-end gap-2">
          <Button
            type="submit"
            data-testid="kanban-settings-save"
            icon="i-lucide-save"
            :label="t('KANBAN.SETTINGS.SAVE')"
            color="blue"
            size="sm"
            :disabled="!form.name.trim()"
            :is-loading="isSaving"
          />
        </div>
      </form>

      <woot-delete-modal
        v-model:show="showDeleteConfirmation"
        :on-close="closeDeleteConfirmation"
        :on-confirm="deleteBoard"
        :title="t('KANBAN.REMOVE_BOARD.TITLE')"
        :message="t('KANBAN.REMOVE_BOARD.MESSAGE')"
        :confirm-text="t('KANBAN.REMOVE_BOARD.CONFIRM')"
        :reject-text="t('KANBAN.REMOVE_BOARD.CANCEL')"
      />

      <woot-modal
        v-model:show="showImportExistingConversationsModal"
        :on-close="closeImportExistingConversationsModal"
      >
        <div
          class="flex w-full max-w-lg flex-col gap-4 rounded-lg bg-n-surface-1 p-6 text-n-slate-12"
          data-testid="kanban-import-existing-conversations-modal"
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
              data-testid="kanban-import-ignore-groups"
              type="checkbox"
              class="size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
            />
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.IGNORE_GROUPS') }}
          </label>

          <p
            v-if="importError"
            data-testid="kanban-import-error"
            class="text-sm text-n-ruby-11"
          >
            {{ importError }}
          </p>

          <div class="flex justify-end gap-2">
            <Button
              type="button"
              data-testid="kanban-import-skip"
              :label="t('KANBAN.SETTINGS.AUTOMATIONS.SKIP_IMPORT')"
              color="slate"
              size="sm"
              :disabled="isImportingConversations"
              @click="closeImportExistingConversationsModal"
            />
            <Button
              type="button"
              data-testid="kanban-import-existing-conversations"
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
    </div>
  </main>
</template>
