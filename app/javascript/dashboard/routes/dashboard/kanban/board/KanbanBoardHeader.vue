<script setup>
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import KanbanBoardIdentityBar from './KanbanBoardIdentityBar.vue';
import KanbanFilterMenu from '../KanbanFilterMenu.vue';

defineProps({
  boards: {
    type: Array,
    default: () => [],
  },
  hasBoards: {
    type: Boolean,
    default: false,
  },
  selectedBoard: {
    type: Object,
    default: null,
  },
  activeBoardId: {
    type: [Number, String],
    default: null,
  },
  currentBoardName: {
    type: String,
    default: '',
  },
  isBoardDropdownOpen: {
    type: Boolean,
    default: false,
  },
  renamingBoardId: {
    type: [Number, String],
    default: null,
  },
  renameValue: {
    type: String,
    default: '',
  },
  isRenamingBoard: {
    type: Boolean,
    default: false,
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  searchInput: {
    type: String,
    default: '',
  },
  isSearchLoading: {
    type: Boolean,
    default: false,
  },
  isMineActive: {
    type: Boolean,
    default: false,
  },
  isTodayActive: {
    type: Boolean,
    default: false,
  },
  todayCardsCount: {
    type: Number,
    default: 0,
  },
  boardFilters: {
    type: Object,
    default: () => ({}),
  },
  inboxFilterOptions: {
    type: Array,
    default: () => [],
  },
  agentFilterOptions: {
    type: Array,
    default: () => [],
  },
  activeBoardFilterCount: {
    type: Number,
    default: 0,
  },
  hasActiveBoardFilters: {
    type: Boolean,
    default: false,
  },
  isCreatingStage: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'goToOverview',
  'closeBoardDropdown',
  'toggleBoardDropdown',
  'startBoardRename',
  'confirmBoardRename',
  'cancelBoardRename',
  'selectBoard',
  'goToCreateBoard',
  'update:searchInput',
  'searchKeydown',
  'toggleMine',
  'toggleToday',
  'updateBoardFilters',
  'clearBoardFilters',
  'openBoardSettings',
  'openStageDraft',
  'update:renameValue',
]);

const { t } = useI18n();
</script>

<template>
  <header
    class="flex min-h-16 flex-col justify-center gap-2 border-b border-n-weak px-4 py-3 md:px-6 lg:flex-row lg:items-center lg:justify-between"
  >
    <div
      class="flex w-full min-w-0 items-center justify-between gap-2 lg:w-auto lg:flex-1 lg:justify-start"
    >
      <KanbanBoardIdentityBar
        :boards="boards"
        :has-boards="hasBoards"
        :active-board-id="activeBoardId"
        :current-board-name="currentBoardName"
        :is-board-dropdown-open="isBoardDropdownOpen"
        :renaming-board-id="renamingBoardId"
        :rename-value="renameValue"
        :is-renaming-board="isRenamingBoard"
        :is-admin="isAdmin"
        @go-to-overview="emit('goToOverview')"
        @close-board-dropdown="emit('closeBoardDropdown')"
        @toggle-board-dropdown="emit('toggleBoardDropdown')"
        @start-board-rename="emit('startBoardRename', $event)"
        @confirm-board-rename="emit('confirmBoardRename')"
        @cancel-board-rename="emit('cancelBoardRename')"
        @select-board="emit('selectBoard', $event)"
        @go-to-create-board="emit('goToCreateBoard')"
        @update:rename-value="emit('update:renameValue', $event)"
      />
      <div
        v-if="selectedBoard"
        class="hidden min-w-[9rem] max-w-64 grow basis-36 ltr:ml-2 rtl:mr-2 lg:block"
      >
        <Input
          :model-value="searchInput"
          type="search"
          size="sm"
          class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:!bg-n-alpha-2 dark:[&>input]:!bg-n-solid-1 [&>input:not(.focus)]:!outline-n-slate-6 dark:[&>input:not(.focus)]:!outline-n-slate-6 [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
          :placeholder="t('KANBAN.SEARCH.PLACEHOLDER')"
          data-testid="kanban-search-input"
          @update:model-value="emit('update:searchInput', $event)"
          @keydown="emit('searchKeydown', $event)"
        >
          <template #prefix>
            <Icon
              :icon="isSearchLoading ? 'i-lucide-loader-2' : 'i-lucide-search'"
              class="absolute top-1/2 size-3.5 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand ltr:left-2.5 rtl:right-2.5"
              :class="{ 'animate-spin': isSearchLoading }"
            />
          </template>
        </Input>
      </div>
      <div
        v-if="selectedBoard"
        class="flex flex-shrink-0 items-center justify-end gap-2 lg:hidden"
      >
        <div
          data-testid="kanban-filter-menu-container"
          class="flex items-center overflow-hidden rounded-lg"
          :class="{
            'border border-n-weak bg-n-alpha-1': hasActiveBoardFilters,
          }"
        >
          <KanbanFilterMenu
            :model-value="boardFilters"
            :inbox-options="inboxFilterOptions"
            :agent-options="agentFilterOptions"
            :active-count="activeBoardFilterCount"
            @update:model-value="emit('updateBoardFilters', $event)"
          />
          <button
            v-if="hasActiveBoardFilters"
            type="button"
            data-testid="kanban-clear-filters"
            class="h-10 border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 ltr:border-l rtl:border-r"
            @click="emit('clearBoardFilters')"
          >
            {{ t('KANBAN.FILTERS.CLEAR_ALL') }}
          </button>
        </div>
        <button
          v-if="isAdmin"
          type="button"
          data-testid="kanban-board-settings-button"
          class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
          :title="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
          @click="emit('openBoardSettings')"
        >
          <span class="i-lucide-settings size-4" />
        </button>
        <button
          type="button"
          data-testid="kanban-create-stage-toggle"
          class="flex size-10 items-center justify-center rounded-lg bg-n-brand text-white disabled:cursor-not-allowed disabled:opacity-50"
          :aria-label="t('KANBAN.ACTIONS.CREATE_STAGE')"
          :title="t('KANBAN.ACTIONS.CREATE_STAGE')"
          :disabled="isCreatingStage"
          @click="emit('openStageDraft')"
        >
          <i class="i-lucide-plus size-4" />
        </button>
      </div>
    </div>
    <div
      v-if="selectedBoard"
      class="flex w-full min-w-0 items-center gap-2 lg:hidden"
    >
      <div class="min-w-0 flex-1">
        <Input
          :model-value="searchInput"
          type="search"
          size="sm"
          class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:!bg-n-alpha-2 dark:[&>input]:!bg-n-solid-1 [&>input:not(.focus)]:!outline-n-slate-6 dark:[&>input:not(.focus)]:!outline-n-slate-6 [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
          :placeholder="t('KANBAN.SEARCH.PLACEHOLDER')"
          data-testid="kanban-search-input"
          @update:model-value="emit('update:searchInput', $event)"
          @keydown="emit('searchKeydown', $event)"
        >
          <template #prefix>
            <Icon
              :icon="isSearchLoading ? 'i-lucide-loader-2' : 'i-lucide-search'"
              class="absolute top-1/2 size-3.5 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand ltr:left-2.5 rtl:right-2.5"
              :class="{ 'animate-spin': isSearchLoading }"
            />
          </template>
        </Input>
      </div>
      <div class="flex flex-shrink-0 items-center gap-2">
        <button
          type="button"
          data-testid="kanban-filter-mine"
          class="inline-flex h-10 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
          :class="
            isMineActive
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          :aria-label="t('KANBAN.FILTERS.MINE')"
          :title="
            t('KANBAN.FILTERS.MINE_TOOLTIP') +
            ' ' +
            t('KANBAN.FILTERS.SHORTCUT_MATCH_ALL_HINT')
          "
          @click="emit('toggleMine')"
        >
          <i class="i-lucide-user-round size-4 flex-shrink-0" />
          <span>{{ t('KANBAN.FILTERS.MINE') }}</span>
        </button>
        <button
          type="button"
          data-testid="kanban-filter-today"
          class="inline-flex h-10 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
          :class="
            isTodayActive
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          :aria-label="t('KANBAN.FILTERS.TODAY')"
          :title="
            t('KANBAN.FILTERS.TODAY_TOOLTIP') +
            ' ' +
            t('KANBAN.FILTERS.SHORTCUT_MATCH_ALL_HINT')
          "
          @click="emit('toggleToday')"
        >
          <i class="i-lucide-calendar-clock size-4 flex-shrink-0" />
          <span>{{ t('KANBAN.FILTERS.TODAY') }}</span>
          <span
            v-if="isTodayActive"
            data-testid="kanban-today-count"
            class="flex h-5 min-w-5 items-center justify-center rounded-full bg-n-brand px-1.5 text-xs font-semibold text-white"
          >
            {{ todayCardsCount }}
          </span>
        </button>
      </div>
    </div>
    <div
      v-if="selectedBoard"
      class="hidden flex-shrink-0 items-center justify-end gap-2 lg:flex"
    >
      <div class="flex items-center gap-2">
        <button
          type="button"
          data-testid="kanban-filter-mine"
          class="inline-flex h-10 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
          :class="
            isMineActive
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          :aria-label="t('KANBAN.FILTERS.MINE')"
          :title="
            t('KANBAN.FILTERS.MINE_TOOLTIP') +
            ' ' +
            t('KANBAN.FILTERS.SHORTCUT_MATCH_ALL_HINT')
          "
          @click="emit('toggleMine')"
        >
          <i class="i-lucide-user-round size-4 flex-shrink-0" />
          <span>{{ t('KANBAN.FILTERS.MINE') }}</span>
        </button>
        <button
          type="button"
          data-testid="kanban-filter-today"
          class="inline-flex h-10 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
          :class="
            isTodayActive
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          :aria-label="t('KANBAN.FILTERS.TODAY')"
          :title="
            t('KANBAN.FILTERS.TODAY_TOOLTIP') +
            ' ' +
            t('KANBAN.FILTERS.SHORTCUT_MATCH_ALL_HINT')
          "
          @click="emit('toggleToday')"
        >
          <i class="i-lucide-calendar-clock size-4 flex-shrink-0" />
          <span>{{ t('KANBAN.FILTERS.TODAY') }}</span>
          <span
            v-if="isTodayActive"
            data-testid="kanban-today-count"
            class="flex h-5 min-w-5 items-center justify-center rounded-full bg-n-brand px-1.5 text-xs font-semibold text-white"
          >
            {{ todayCardsCount }}
          </span>
        </button>
      </div>
      <div
        data-testid="kanban-filter-menu-container"
        class="flex items-center overflow-hidden rounded-lg"
        :class="{
          'border border-n-weak bg-n-alpha-1': hasActiveBoardFilters,
        }"
      >
        <KanbanFilterMenu
          :model-value="boardFilters"
          :inbox-options="inboxFilterOptions"
          :agent-options="agentFilterOptions"
          :active-count="activeBoardFilterCount"
          @update:model-value="emit('updateBoardFilters', $event)"
        />
        <button
          v-if="hasActiveBoardFilters"
          type="button"
          data-testid="kanban-clear-filters"
          class="h-10 border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 ltr:border-l rtl:border-r"
          @click="emit('clearBoardFilters')"
        >
          {{ t('KANBAN.FILTERS.CLEAR_ALL') }}
        </button>
      </div>
      <button
        v-if="isAdmin"
        type="button"
        data-testid="kanban-board-settings-button"
        class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
        :aria-label="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
        :title="t('KANBAN.ACTIONS.BOARD_SETTINGS')"
        @click="emit('openBoardSettings')"
      >
        <span class="i-lucide-settings size-4" />
      </button>
      <button
        type="button"
        data-testid="kanban-create-stage-toggle"
        class="flex size-10 items-center justify-center rounded-lg bg-n-brand text-white disabled:cursor-not-allowed disabled:opacity-50"
        :aria-label="t('KANBAN.ACTIONS.CREATE_STAGE')"
        :title="t('KANBAN.ACTIONS.CREATE_STAGE')"
        :disabled="isCreatingStage"
        @click="emit('openStageDraft')"
      >
        <i class="i-lucide-plus size-4" />
      </button>
    </div>
  </header>
</template>
