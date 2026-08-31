<script setup>
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

defineProps({
  boards: {
    type: Array,
    default: () => [],
  },
  hasBoards: {
    type: Boolean,
    default: false,
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
  'update:renameValue',
]);

const { t } = useI18n();
</script>

<template>
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
</template>
