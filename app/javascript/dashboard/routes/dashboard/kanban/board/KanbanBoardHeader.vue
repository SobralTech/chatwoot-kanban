<script setup>
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
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
      <div class="flex min-w-0 flex-shrink items-center gap-1">
        <NextButton
          data-testid="kanban-back-to-overview"
          icon="i-lucide-chevron-left"
          variant="ghost"
          color="slate"
          size="md"
          class="flex-shrink-0 [&>span]:size-5"
          :aria-label="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
          :title="t('KANBAN.ACTIONS.BACK_TO_OVERVIEW')"
          @click="emit('goToOverview')"
        />
        <OnClickOutside @trigger="emit('closeBoardDropdown')">
          <div class="relative inline-flex min-w-0 max-w-full flex-col">
            <button
              type="button"
              data-testid="kanban-board-switcher"
              class="inline-flex min-w-0 max-w-full items-center gap-2 rounded-md px-1 py-1 text-left text-base font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="!hasBoards"
              @click="emit('toggleBoardDropdown')"
            >
              <span class="min-w-0 truncate">{{ currentBoardName }}</span>
              <i
                class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11 transition-transform"
                :class="{ 'rotate-180': isBoardDropdownOpen }"
              />
            </button>
            <div
              v-if="isBoardDropdownOpen"
              data-testid="kanban-board-switcher-dropdown"
              class="absolute left-0 top-full z-50 mt-2 w-96 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border-0 bg-n-alpha-3 shadow-lg outline outline-1 outline-n-container backdrop-blur-[100px]"
            >
              <div class="max-h-80 overflow-y-auto">
                <div
                  v-for="board in boards"
                  :key="board.id"
                  class="group flex w-full items-center gap-2 px-4 py-3 text-sm text-n-slate-12 hover:bg-n-alpha-1"
                >
                  <template v-if="renamingBoardId === board.id">
                    <InlineInput
                      :model-value="renameValue"
                      focus-on-mount
                      data-testid="kanban-board-rename-input"
                      :placeholder="t('KANBAN.ACTIONS.RENAME_BOARD')"
                      class="min-w-0 flex-1"
                      @update:model-value="emit('update:renameValue', $event)"
                      @enter-press="emit('confirmBoardRename')"
                      @escape-press="emit('cancelBoardRename')"
                    />
                    <NextButton
                      icon="i-lucide-check"
                      ghost
                      xs
                      slate
                      data-testid="kanban-board-rename-confirm"
                      :is-loading="isRenamingBoard"
                      :disabled="isRenamingBoard"
                      :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD_CONFIRM')"
                      :title="t('KANBAN.ACTIONS.RENAME_BOARD_CONFIRM')"
                      @click="emit('confirmBoardRename')"
                    />
                    <NextButton
                      icon="i-lucide-x"
                      ghost
                      xs
                      slate
                      :disabled="isRenamingBoard"
                      :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD_CANCEL')"
                      :title="t('KANBAN.ACTIONS.RENAME_BOARD_CANCEL')"
                      @click="emit('cancelBoardRename')"
                    />
                  </template>
                  <template v-else>
                    <button
                      type="button"
                      class="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-left"
                      :title="board.name"
                      @click="emit('selectBoard', board.id)"
                    >
                      {{ board.name }}
                    </button>
                    <NextButton
                      v-if="isAdmin"
                      icon="i-lucide-pencil"
                      ghost
                      xs
                      slate
                      data-testid="kanban-board-rename-start"
                      class="opacity-0 transition-opacity focus:opacity-100 group-hover:opacity-100"
                      :aria-label="t('KANBAN.ACTIONS.RENAME_BOARD')"
                      :title="t('KANBAN.ACTIONS.RENAME_BOARD')"
                      @click.stop="emit('startBoardRename', board)"
                    />
                    <i
                      v-if="board.id === activeBoardId"
                      class="i-lucide-check size-4 flex-shrink-0 text-n-brand"
                    />
                  </template>
                </div>
              </div>
              <div v-if="isAdmin" class="border-t border-n-weak p-2">
                <button
                  type="button"
                  class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm font-medium text-n-brand hover:bg-n-alpha-1"
                  data-testid="kanban-board-switcher-create-new"
                  @click="emit('goToCreateBoard')"
                >
                  <i class="i-lucide-plus size-4" />
                  {{ t('KANBAN.OVERVIEW.CREATE_BOARD') }}
                </button>
              </div>
            </div>
          </div>
        </OnClickOutside>
      </div>
      <div
        v-if="selectedBoard"
        class="hidden min-w-[9rem] max-w-64 grow basis-36 ltr:ml-2 rtl:mr-2 lg:block"
      >
        <Input
          :model-value="searchInput"
          type="search"
          size="sm"
          class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
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
          class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
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
