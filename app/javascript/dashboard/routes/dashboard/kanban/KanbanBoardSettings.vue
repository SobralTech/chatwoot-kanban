<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';

import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Button from 'dashboard/components-next/button/Button.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const currentRole = useMapGetter('auth/getCurrentRole');
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const isAdmin = computed(() => currentRole.value === 'administrator');

const isLoading = ref(false);
const isSaving = ref(false);
const isDeleting = ref(false);
const loadError = ref('');
const saveError = ref('');
const showDeleteConfirmation = ref(false);

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

const fetchSettings = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const [response] = await Promise.all([
      KanbanBoardsAPI.getSettings(boardId.value),
      store.dispatch('agents/get'),
      store.dispatch('inboxes/get'),
    ]);
    applySettings(response.data);
  } catch (error) {
    loadError.value = getErrorMessage(error, t('KANBAN.SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
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
    <div
      class="mx-auto flex w-full max-w-4xl flex-col gap-6 overflow-y-auto p-8"
    >
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
          <label
            class="flex items-start gap-3 rounded-md border border-n-weak bg-n-surface-2 px-3 py-2 text-sm text-n-slate-12"
          >
            <input
              v-model="form.autoCreateCardsFromConversations"
              data-testid="kanban-settings-auto-create"
              type="checkbox"
              class="mt-1 size-4 rounded border-n-weak text-n-brand focus:ring-n-brand"
            />
            <span class="font-medium">
              {{ t('KANBAN.SETTINGS.GENERAL.AUTO_CREATE') }}
            </span>
          </label>
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

        <section class="grid gap-2 border-b border-n-weak pb-6">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11">
            {{ t('KANBAN.SETTINGS.AUTOMATIONS.COMING_SOON') }}
          </p>
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
    </div>
  </main>
</template>
