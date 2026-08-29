<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();
const { isAdmin } = useAdmin();

const boards = useMapGetter('kanbanBoards/kanbanBoards');
const isLoading = useMapGetter('kanbanBoards/kanbanBoardsLoading');
const error = useMapGetter('kanbanBoards/kanbanBoardsError');

const hasFetched = ref(false);

const hasBoards = computed(() => boards.value.length > 0);

const goToCreateBoard = () => {
  router.push({
    name: 'kanban_board_create_form',
    params: { accountId: route.params.accountId },
  });
};

const openBoard = boardId => {
  router.push({
    name: 'kanban_board_show',
    params: {
      accountId: route.params.accountId,
      boardId,
    },
  });
};

const previewItems = (items = [], limit = 4) => items.slice(0, limit);
const extraItemsCount = (items = [], limit = 4) =>
  Math.max(items.length - limit, 0);

const inboxIcon = inbox =>
  getInboxIconByType(inbox.channelType, inbox.medium, 'line', inbox.name);

const allInboxRuleSummary = board => {
  const ruleNames = board.allInboxRuleNames || [];
  if (!ruleNames.length) return '';

  const additionalCount = ruleNames.length - 1;
  if (additionalCount) {
    return t('KANBAN.OVERVIEW.ALL_INBOXES_VIA_RULES', {
      rule: ruleNames[0],
      count: additionalCount,
    });
  }

  return t('KANBAN.OVERVIEW.ALL_INBOXES_VIA_RULE', {
    rule: ruleNames[0],
  });
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
  <main
    class="flex h-full min-h-0 w-full overflow-y-auto no-scrollbar bg-n-surface-1 text-n-slate-12"
  >
    <div
      class="mx-auto flex min-h-full w-full max-w-7xl flex-col gap-6 px-6 py-8 lg:px-10"
    >
      <header
        v-if="hasBoards"
        class="flex flex-wrap items-center justify-between gap-4"
      >
        <div class="min-w-0">
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('KANBAN.OVERVIEW.TITLE') }}
          </h1>
        </div>
        <div class="flex flex-shrink-0 items-center gap-4">
          <Button
            v-if="isAdmin"
            icon="i-lucide-plus"
            data-testid="overview-create-board-button"
            :label="t('KANBAN.OVERVIEW.CREATE_BOARD')"
            color="blue"
            size="sm"
            @click="goToCreateBoard"
          />
        </div>
      </header>

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
          :label="t('KANBAN.ACTIONS.RETRY')"
          color="slate"
          size="sm"
          @click="retryFetch"
        />
      </div>

      <div
        v-else-if="!hasBoards && hasFetched"
        class="flex flex-1 items-center justify-center py-8"
      >
        <section
          data-testid="overview-empty-state"
          class="flex w-full max-w-xl flex-col items-center rounded-xl border border-n-weak bg-n-surface-2 p-6 text-center shadow-lg sm:p-8"
        >
          <div
            class="mb-5 flex size-14 items-center justify-center rounded-xl bg-n-brand text-white shadow-sm"
          >
            <i class="i-lucide-panels-top-left size-7" aria-hidden="true" />
          </div>

          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('KANBAN.OVERVIEW.EMPTY_TITLE') }}
          </h1>
          <p class="mt-2 max-w-md text-sm leading-6 text-n-slate-11">
            {{ t('KANBAN.OVERVIEW.EMPTY_DESCRIPTION') }}
          </p>

          <div
            class="my-6 flex w-full gap-3 rounded-lg border border-n-weak bg-n-alpha-2 p-4 text-left"
          >
            <div
              class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-brand/10 text-n-blue-11"
            >
              <i class="i-lucide-lightbulb size-4" aria-hidden="true" />
            </div>
            <div class="min-w-0">
              <h2 class="text-sm font-semibold text-n-slate-12">
                {{ t('KANBAN.OVERVIEW.TIP_TITLE') }}
              </h2>
              <p class="mt-1 text-sm leading-5 text-n-slate-11">
                {{ t('KANBAN.OVERVIEW.TIP_DESCRIPTION') }}
              </p>
            </div>
          </div>

          <Button
            v-if="isAdmin"
            icon="i-lucide-plus"
            data-testid="overview-create-board-button"
            class="w-full"
            :label="t('KANBAN.ACTIONS.CONFIRM_CREATE_BOARD')"
            color="blue"
            size="md"
            @click="goToCreateBoard"
          />
        </section>
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
                    count: board.cardsCount ?? 0,
                  })
                }}
              </span>
            </div>

            <div class="flex flex-wrap items-center gap-3 lg:justify-end">
              <div class="flex items-center" data-testid="overview-agent-list">
                <template v-if="board.visibilityMode !== 'selected_agents'">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                  >
                    <i class="i-lucide-users size-3.5" />
                    {{ t('KANBAN.SETTINGS.AGENTS.ALL') }}
                  </span>
                </template>
                <template v-else>
                  <Avatar
                    v-for="user in previewItems(board.visibleUsers)"
                    :key="user.id"
                    :name="user.name"
                    :src="user.avatarUrl || ''"
                    :size="28"
                    rounded-full
                    class="-ml-2 first:ml-0 ring-2 ring-n-surface-2"
                    data-testid="overview-agent-avatar"
                  />
                  <span
                    v-if="extraItemsCount(board.visibleUsers)"
                    class="-ml-2 inline-flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-xs font-medium text-n-slate-11 ring-2 ring-n-surface-2"
                  >
                    {{
                      t('KANBAN.OVERVIEW.EXTRA_COUNT', {
                        count: extraItemsCount(board.visibleUsers),
                      })
                    }}
                  </span>
                </template>
              </div>

              <div
                class="flex flex-wrap items-center gap-2"
                data-testid="overview-inbox-list"
              >
                <template v-if="board.inboxScopeMode !== 'selected_inboxes'">
                  <span
                    class="inline-flex min-w-0 max-w-80 items-center gap-1.5 rounded-full border border-n-weak bg-n-surface-1 px-2.5 py-1 text-xs font-medium text-n-slate-11"
                    data-testid="overview-inbox-pill"
                  >
                    <i class="i-lucide-inbox size-3.5 flex-shrink-0" />
                    <span class="flex-shrink-0">
                      {{ t('KANBAN.SETTINGS.INBOXES.ALL') }}
                    </span>
                    <span
                      v-if="board.allInboxRuleNames?.length"
                      class="truncate font-normal text-n-slate-10"
                      :title="board.allInboxRuleNames.join(', ')"
                    >
                      {{ allInboxRuleSummary(board) }}
                    </span>
                  </span>
                </template>
                <template v-else>
                  <span
                    v-for="inbox in previewItems(board.allowedInboxes)"
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
                    v-if="extraItemsCount(board.allowedInboxes)"
                    class="inline-flex items-center rounded-full bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-11"
                  >
                    {{
                      t('KANBAN.OVERVIEW.EXTRA_COUNT', {
                        count: extraItemsCount(board.allowedInboxes),
                      })
                    }}
                  </span>
                </template>
              </div>
            </div>
          </div>

          <div
            v-if="board.stagesSummary?.length"
            class="flex flex-wrap gap-2"
            data-testid="overview-stage-list"
          >
            <span
              v-for="stage in board.stagesSummary"
              :key="stage.id"
              class="inline-flex max-w-full items-center gap-2 rounded-full border border-n-weak bg-n-surface-1 px-3 py-1.5 text-xs font-medium text-n-slate-11"
              data-testid="overview-stage-pill"
            >
              <span
                class="size-2 flex-shrink-0 rounded-full"
                :style="{ backgroundColor: stage.color }"
              />
              <span class="truncate">{{ stage.name }}</span>
              <span
                class="inline-flex min-w-5 justify-center rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-[11px] font-semibold text-n-slate-12"
              >
                {{ stage.cardsCount ?? 0 }}
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
