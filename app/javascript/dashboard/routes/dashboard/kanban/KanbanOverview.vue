<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import camelcaseKeys from 'camelcase-keys';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import { getKanbanStageColorClass } from 'dashboard/helper/kanbanStageColors';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

const currentRole = useMapGetter('auth/getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const boards = useMapGetter('kanbanBoards/kanbanBoards');
const isLoading = useMapGetter('kanbanBoards/kanbanBoardsLoading');
const error = useMapGetter('kanbanBoards/kanbanBoardsError');

const showCreateForm = ref(false);
const newBoardName = ref('');
const isCreatingBoard = ref(false);
const isSavingAgentCreationSetting = ref(false);
const allowAgentKanbanBoardCreation = ref(null);
const hasFetched = ref(false);

const hasBoards = computed(() => boards.value.length > 0);
const canCreateBoard = computed(
  () => isAdmin.value || allowAgentKanbanBoardCreation.value === true
);

const openBoard = boardId => {
  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
  });
};

const boardCardsCount = board => board.cards_count ?? board.cardsCount ?? 0;
const boardStages = board => board.stages_summary || board.stagesSummary || [];
const boardUsers = board => board.visible_users || board.visibleUsers || [];
const boardInboxes = board =>
  board.allowed_inboxes || board.allowedInboxes || [];
const boardVisibilityMode = board =>
  board.visibility_mode || board.visibilityMode || 'all_agents';
const boardInboxScopeMode = board =>
  board.inbox_scope_mode || board.inboxScopeMode || 'all_inboxes';

const previewItems = (items, limit = 4) => items.slice(0, limit);
const extraItemsCount = (items, limit = 4) => Math.max(items.length - limit, 0);

const inboxIcon = inbox =>
  getInboxIconByType(
    inbox.channel_type || inbox.channelType,
    inbox.medium,
    'line'
  );

const createBoard = async () => {
  const name = newBoardName.value.trim();
  if (!name || isCreatingBoard.value || !canCreateBoard.value) return;

  isCreatingBoard.value = true;

  try {
    const response = await KanbanBoardsAPI.create({
      kanban_board: {
        name,
        position: boards.value.length,
      },
    });
    const board = camelcaseKeys(response.data || {}, { deep: true });
    newBoardName.value = '';
    showCreateForm.value = false;
    store.dispatch('kanbanBoards/refreshBoards');
    router.push({
      name: 'kanban_board_show',
      params: {
        accountId: route.params.accountId,
        boardId: board.id,
      },
    });
    useAlert(t('KANBAN.ACTIONS.CREATE_BOARD_SUCCESS'));
  } catch (err) {
    const message =
      err?.response?.data?.error || t('KANBAN.ACTIONS.CREATE_BOARD_ERROR');
    useAlert(message);
  } finally {
    isCreatingBoard.value = false;
  }
};

const fetchAccountSettings = async () => {
  const response = await KanbanBoardsAPI.getAccountSettings();
  const settings = camelcaseKeys(response.data || {});
  allowAgentKanbanBoardCreation.value =
    settings.allowAgentKanbanBoardCreation === true;
};

const updateAgentCreationSetting = async event => {
  const previousValue = allowAgentKanbanBoardCreation.value;
  const nextValue = event.target.checked;

  allowAgentKanbanBoardCreation.value = nextValue;
  isSavingAgentCreationSetting.value = true;

  try {
    const response = await KanbanBoardsAPI.updateAccountSettings({
      account: {
        allow_agent_kanban_board_creation: nextValue,
      },
    });
    const settings = camelcaseKeys(response.data || {});
    allowAgentKanbanBoardCreation.value =
      settings.allowAgentKanbanBoardCreation === true;
  } catch (err) {
    allowAgentKanbanBoardCreation.value = previousValue;
    const message =
      err?.response?.data?.error ||
      t('KANBAN.OVERVIEW.AGENT_CREATION_SETTING_ERROR');
    useAlert(message);
  } finally {
    isSavingAgentCreationSetting.value = false;
  }
};

const retryFetch = () => {
  store.dispatch('kanbanBoards/fetchBoards');
};

onMounted(async () => {
  hasFetched.value = true;
  try {
    await Promise.all([
      store.dispatch('kanbanBoards/fetchBoards'),
      fetchAccountSettings(),
    ]);
  } catch {
    // Error is handled by the store's error state
  }
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <div
      class="mx-auto flex w-full max-w-7xl flex-col gap-6 px-6 py-8 lg:px-10"
    >
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('KANBAN.OVERVIEW.TITLE') }}
          </h1>
        </div>
        <div class="flex flex-shrink-0 items-center gap-4">
          <label
            v-if="isAdmin"
            class="flex items-center gap-2 text-sm font-medium text-n-slate-11"
          >
            <input
              type="checkbox"
              class="h-4 w-4 cursor-pointer rounded border border-n-weak accent-n-brand disabled:cursor-not-allowed disabled:opacity-50"
              data-testid="overview-agent-creation-toggle"
              :checked="allowAgentKanbanBoardCreation === true"
              :disabled="isSavingAgentCreationSetting"
              @change="updateAgentCreationSetting"
            />
            {{ t('KANBAN.OVERVIEW.ALLOW_AGENT_CREATION') }}
          </label>
          <Button
            v-if="canCreateBoard && !showCreateForm"
            icon="i-lucide-plus"
            data-testid="overview-create-board-button"
            :label="t('KANBAN.OVERVIEW.CREATE_BOARD')"
            color="primary"
            size="sm"
            @click="showCreateForm = true"
          />
        </div>
      </header>

      <form
        v-if="showCreateForm"
        class="flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-4 sm:flex-row"
        @submit.prevent="createBoard"
      >
        <input
          v-model="newBoardName"
          type="text"
          class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10 focus:border-n-brand"
          :placeholder="t('KANBAN.ACTIONS.BOARD_NAME_PLACEHOLDER')"
        />
        <button
          type="submit"
          class="flex flex-shrink-0 items-center justify-center gap-1 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!newBoardName.trim() || isCreatingBoard"
        >
          <i class="i-lucide-check size-4" />
          {{ t('KANBAN.ACTIONS.CREATE_BOARD') }}
        </button>
        <button
          type="button"
          class="flex flex-shrink-0 items-center justify-center gap-1 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12"
          @click="showCreateForm = false"
        >
          <i class="i-lucide-x size-4" />
          {{ t('KANBAN.ACTIONS.CANCEL') }}
        </button>
      </form>

      <div
        v-if="isLoading"
        class="flex items-center justify-center py-16 text-sm text-n-slate-11"
      >
        {{ t('KANBAN.OVERVIEW.LOADING') }}
      </div>

      <div
        v-else-if="error"
        class="flex flex-col items-center gap-4 py-16 text-center"
      >
        <p class="text-sm text-n-ruby-11">
          {{ t('KANBAN.OVERVIEW.ERROR') }}
        </p>
        <Button
          label="KANBAN.ACTIONS.RETRY"
          color="secondary"
          size="sm"
          @click="retryFetch"
        />
      </div>

      <div
        v-else-if="!hasBoards && hasFetched"
        class="flex flex-col items-center gap-4 py-16 text-center"
      >
        <p class="text-sm text-n-slate-11">
          {{
            isAdmin
              ? t('KANBAN.OVERVIEW.EMPTY_ADMIN')
              : t('KANBAN.OVERVIEW.EMPTY_AGENT')
          }}
        </p>
        <Button
          v-if="canCreateBoard"
          icon="i-lucide-plus"
          data-testid="overview-create-board-button"
          :label="t('KANBAN.OVERVIEW.CREATE_BOARD')"
          color="primary"
          size="sm"
          @click="showCreateForm = true"
        />
      </div>

      <div v-else-if="hasBoards" class="flex flex-col gap-3">
        <button
          v-for="board in boards"
          :key="board.id"
          type="button"
          data-testid="overview-board-card"
          class="group flex w-full flex-col gap-5 rounded-lg border border-n-weak bg-n-surface-2 p-5 text-left transition-colors hover:border-n-brand hover:bg-n-alpha-1 focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="openBoard(board.id)"
        >
          <div
            class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"
          >
            <div class="flex min-w-0 flex-1 flex-wrap items-center gap-3">
              <span class="truncate text-base font-semibold text-n-slate-12">
                {{ board.name }}
              </span>
              <span
                class="inline-flex items-center rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                data-testid="overview-cards-count"
              >
                {{
                  t('KANBAN.OVERVIEW.OPPORTUNITIES_COUNT', {
                    count: boardCardsCount(board),
                  })
                }}
              </span>
            </div>

            <div class="flex flex-wrap items-center gap-3 lg:justify-end">
              <div class="flex items-center" data-testid="overview-agent-list">
                <template v-if="boardVisibilityMode(board) === 'all_agents'">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                  >
                    <i class="i-lucide-users size-3.5" />
                    {{ t('KANBAN.SETTINGS.AGENTS.ALL') }}
                  </span>
                </template>
                <template v-else>
                  <Avatar
                    v-for="user in previewItems(boardUsers(board))"
                    :key="user.id"
                    :name="user.name"
                    :src="user.avatar_url || user.avatarUrl || ''"
                    :size="28"
                    rounded-full
                    class="-ml-2 first:ml-0 ring-2 ring-n-surface-2"
                    data-testid="overview-agent-avatar"
                  />
                  <span
                    v-if="extraItemsCount(boardUsers(board))"
                    class="-ml-2 inline-flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-xs font-medium text-n-slate-11 ring-2 ring-n-surface-2"
                  >
                    {{
                      t('KANBAN.OVERVIEW.EXTRA_COUNT', {
                        count: extraItemsCount(boardUsers(board)),
                      })
                    }}
                  </span>
                </template>
              </div>

              <div
                class="flex flex-wrap items-center gap-2"
                data-testid="overview-inbox-list"
              >
                <template v-if="boardInboxScopeMode(board) === 'all_inboxes'">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                    data-testid="overview-inbox-pill"
                  >
                    <i class="i-lucide-inbox size-3.5" />
                    {{ t('KANBAN.SETTINGS.INBOXES.ALL') }}
                  </span>
                </template>
                <template v-else>
                  <span
                    v-for="inbox in previewItems(boardInboxes(board))"
                    :key="inbox.id"
                    class="inline-flex max-w-40 items-center gap-1.5 rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                    data-testid="overview-inbox-pill"
                  >
                    <i
                      :class="inboxIcon(inbox)"
                      class="size-3.5 flex-shrink-0"
                    />
                    <span class="truncate">{{ inbox.name }}</span>
                  </span>
                  <span
                    v-if="extraItemsCount(boardInboxes(board))"
                    class="inline-flex items-center rounded-full bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-11"
                  >
                    {{
                      t('KANBAN.OVERVIEW.EXTRA_COUNT', {
                        count: extraItemsCount(boardInboxes(board)),
                      })
                    }}
                  </span>
                </template>
              </div>
            </div>
          </div>

          <div
            v-if="boardStages(board).length"
            class="flex flex-wrap gap-2"
            data-testid="overview-stage-list"
          >
            <span
              v-for="stage in boardStages(board)"
              :key="stage.id"
              class="inline-flex max-w-full items-center gap-2 rounded-full border border-n-weak bg-n-surface-1 px-3 py-1.5 text-xs font-medium text-n-slate-11"
              data-testid="overview-stage-pill"
            >
              <span
                class="size-2 flex-shrink-0 rounded-full"
                :class="getKanbanStageColorClass(stage.color)"
              />
              <span class="truncate">{{ stage.name }}</span>
              <span
                class="inline-flex min-w-5 justify-center rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[11px] font-semibold text-n-slate-12"
              >
                {{ stage.cards_count ?? stage.cardsCount ?? 0 }}
              </span>
            </span>
          </div>
          <p v-else class="text-sm text-n-slate-11">
            {{ t('KANBAN.OVERVIEW.EMPTY_STAGES') }}
          </p>
        </button>
      </div>
    </div>
  </main>
</template>
