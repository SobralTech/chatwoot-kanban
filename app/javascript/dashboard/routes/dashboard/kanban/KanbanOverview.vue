<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import camelcaseKeys from 'camelcase-keys';
import Button from 'dashboard/components-next/button/Button.vue';

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
const hasFetched = ref(false);

const hasBoards = computed(() => boards.value.length > 0);

const openBoard = boardId => {
  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
  });
};

const createBoard = async () => {
  const name = newBoardName.value.trim();
  if (!name || isCreatingBoard.value) return;

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

const retryFetch = () => {
  store.dispatch('kanbanBoards/fetchBoards');
};

onMounted(async () => {
  hasFetched.value = true;
  try {
    await store.dispatch('kanbanBoards/fetchBoards');
  } catch {
    // Error is handled by the store's error state
  }
});
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-6 p-8">
      <header class="flex items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-2xl font-medium text-n-slate-12">
            {{ t('KANBAN.OVERVIEW.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('KANBAN.OVERVIEW.DESCRIPTION') }}
          </p>
        </div>
        <div v-if="isAdmin" class="flex flex-shrink-0 gap-2">
          <Button
            v-if="!showCreateForm"
            icon="i-lucide-plus"
            label="KANBAN.OVERVIEW.CREATE_BOARD"
            color="primary"
            size="sm"
            @click="showCreateForm = true"
          />
        </div>
      </header>

      <form
        v-if="showCreateForm"
        class="flex gap-2 rounded-lg border border-n-weak bg-n-surface-2 p-4"
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
          class="flex flex-shrink-0 items-center gap-1 rounded-md bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!newBoardName.trim() || isCreatingBoard"
        >
          <i class="i-lucide-check size-4" />
          {{ t('KANBAN.ACTIONS.CREATE_BOARD') }}
        </button>
        <button
          type="button"
          class="flex flex-shrink-0 items-center gap-1 rounded-md border border-n-weak px-3 py-2 text-sm font-medium text-n-slate-12"
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
          v-if="isAdmin"
          icon="i-lucide-plus"
          label="KANBAN.OVERVIEW.CREATE_BOARD"
          color="primary"
          size="sm"
          @click="showCreateForm = true"
        />
      </div>

      <div
        v-else-if="hasBoards"
        class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
      >
        <button
          v-for="board in boards"
          :key="board.id"
          type="button"
          class="flex min-h-32 flex-col gap-2 rounded-lg border border-n-weak bg-n-surface-2 p-5 text-left transition-colors hover:border-n-brand hover:bg-n-alpha-1"
          @click="openBoard(board.id)"
        >
          <span class="text-base font-medium text-n-slate-12">
            {{ board.name }}
          </span>
          <p
            v-if="board.description"
            class="line-clamp-2 text-sm text-n-slate-11"
          >
            {{ board.description }}
          </p>
        </button>
      </div>
    </div>
  </main>
</template>
