<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanBoardSwitcher } from 'dashboard/composables/useKanbanBoardSwitcher';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import KanbanBoardIdentityBar from './KanbanBoardIdentityBar.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isAdmin } = useAdmin();

const agents = useMapGetter('agents/getAgents');
const boards = useMapGetter('kanbanBoards/kanbanBoards');
const inboxes = useMapGetter('inboxes/getAllInboxes');

const hasError = ref(false);
const selectedBoard = ref(null);

const activeBoardId = computed(() => Number(route.params.boardId) || null);
const hasBoards = computed(() => boards.value.length > 0);
const currentBoardName = computed(
  () => selectedBoard.value?.name || t('KANBAN.NO_BOARD_SELECTED')
);

// These routes always carry a :boardId, so the switcher's fetch lands here
// rather than on its "pick the first board" branch; the board itself needs no
// snapshot, only its name for the identity bar.
const showBoardWithSnapshot = async boardId => {
  selectedBoard.value =
    boards.value.find(board => board.id === boardId) || null;
};

const {
  isBoardDropdownOpen,
  isRenamingBoard,
  renameValue,
  renamingBoardId,
  cancelBoardRename,
  closeBoardDropdown,
  confirmBoardRename,
  fetchBoards,
  goToCreateBoard,
  goToOverview,
  selectBoard,
  startBoardRename,
  toggleBoardDropdown,
} = useKanbanBoardSwitcher({
  activeBoardId,
  agents,
  boards,
  hasBoards,
  hasError,
  inboxes,
  route,
  router,
  selectedBoard,
  showBoardWithSnapshot,
  store,
  t,
});

onMounted(fetchBoards);
</script>

<template>
  <main class="flex h-full min-h-0 w-full bg-n-surface-1 text-n-slate-12">
    <section class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex min-h-16 flex-col justify-center gap-2 border-b border-n-weak px-4 py-3 md:px-6 lg:flex-row lg:items-center lg:justify-between"
      >
        <div
          class="flex w-full min-w-0 items-center justify-between gap-2 lg:w-auto lg:flex-1 lg:justify-start"
        >
          <KanbanBoardIdentityBar
            v-model:rename-value="renameValue"
            :boards="boards"
            :has-boards="hasBoards"
            :active-board-id="activeBoardId"
            :current-board-name="currentBoardName"
            :is-board-dropdown-open="isBoardDropdownOpen"
            :renaming-board-id="renamingBoardId"
            :is-renaming-board="isRenamingBoard"
            :is-admin="isAdmin"
            @go-to-overview="goToOverview"
            @close-board-dropdown="closeBoardDropdown"
            @toggle-board-dropdown="toggleBoardDropdown"
            @start-board-rename="startBoardRename"
            @confirm-board-rename="confirmBoardRename"
            @cancel-board-rename="cancelBoardRename"
            @select-board="selectBoard"
            @go-to-create-board="goToCreateBoard"
          />
        </div>
      </header>

      <div
        v-if="hasError"
        class="flex flex-1 items-center justify-center p-6 text-sm text-n-ruby-11"
      >
        {{ t('KANBAN.ERROR') }}
      </div>
      <slot v-else />
    </section>
  </main>
</template>
