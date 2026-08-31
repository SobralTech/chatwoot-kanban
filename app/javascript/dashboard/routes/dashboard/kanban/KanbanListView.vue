<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useKanbanBoardFiltersState } from 'dashboard/composables/useKanbanBoardFiltersState';
import { useKanbanCardFields } from 'dashboard/composables/useKanbanCardFields';
import { useKanbanListData } from 'dashboard/composables/useKanbanListData';
import { useKanbanStageOrder } from 'dashboard/composables/useKanbanStageOrder';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanBoardViewShell from './board/KanbanBoardViewShell.vue';
import KanbanFilterMenu from './KanbanFilterMenu.vue';
import KanbanListGroup from './list/KanbanListGroup.vue';
import KanbanListGroupBySelect from './list/KanbanListGroupBySelect.vue';
import KanbanOpportunityPanel from './opportunity/KanbanOpportunityPanel.vue';
import KanbanOpportunityPicker from './KanbanOpportunityPicker.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { isAdmin } = useAdmin();

const currentUserId = useMapGetter('getCurrentUserID');
const agents = useMapGetter('agents/getAgents');
const boards = useMapGetter('kanbanBoards/kanbanBoards');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const storeLabels = useMapGetter('labels/getLabels');

const board = ref(null);
const isFetchingBoard = ref(false);
const selectedCardId = ref(null);
const addItemStage = ref(null);
const cardPendingRemoval = ref(null);
const showRemoveCardConfirmation = ref(false);
const busyCardIds = ref(new Set());

const boardId = computed(() => Number(route.params.boardId));
const stages = computed(() => board.value?.stages || []);
const assignableUsers = computed(() => board.value?.assignableUsers || []);

const {
  activeBoardFilterCount,
  activeSearchTerm,
  boardFilters,
  currentFilterParams,
  emptyBoardFilters,
  hasActiveBoardFilters,
  isSearchLoading,
  normalizeBoardFilters,
  scheduleSearch,
  searchInput,
} = useKanbanBoardFiltersState({
  currentUserId,
  isFetchingBoard,
  stages,
});

const {
  fetchList,
  groupBy,
  groups,
  isGroupLoading,
  isLoading,
  loadMoreForGroup,
} = useKanbanListData({
  board,
  boardId,
  currentFilterParams,
  isLoading: isFetchingBoard,
});

const { isTerminalStage } = useKanbanStageOrder({
  stages,
  wonStageId: computed(() => board.value?.wonStageId),
  lostStageId: computed(() => board.value?.lostStageId),
});

const boardAllowedInboxIds = computed(() => board.value?.allowedInboxIds || []);
const inboxFilterOptions = computed(() => {
  const availableInboxes =
    board.value?.inboxScopeMode === 'selected_inboxes'
      ? inboxes.value.filter(inbox =>
          boardAllowedInboxIds.value.includes(inbox.id)
        )
      : inboxes.value;

  return availableInboxes.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }));
});
const agentFilterOptions = computed(() =>
  agents.value.map(agent => ({
    value: agent.id,
    label: agent.name || agent.email,
  }))
);

// Creating a card puts it in a stage, so only a stage group can offer it - and a
// card only reaches a terminal stage by being won or lost.
const canAddCardInGroup = group =>
  !!group.stageId && !isTerminalStage({ id: group.stageId });

const loadList = async () => {
  try {
    await fetchList();
  } catch (error) {
    useAlert(t('KANBAN.ERROR'));
  }
};

const runSearch = async () => {
  const term = searchInput.value.trim();
  const nextTerm = term.length >= 2 ? term : '';
  if (nextTerm === activeSearchTerm.value) return;

  activeSearchTerm.value = nextTerm;
  await loadList();
};

const updateBoardFilters = async filters => {
  boardFilters.value = normalizeBoardFilters(filters);
  await loadList();
};

const clearBoardFilters = () => updateBoardFilters(emptyBoardFilters());

const onSearchKeydown = event => {
  if (event.key !== 'Escape' || searchInput.value === '') return;

  event.preventDefault();
  searchInput.value = '';
};

const openCard = card => {
  selectedCardId.value = card.id;
};

const isCardBusy = card => busyCardIds.value.has(card.id);

const setCardBusy = (card, busy) => {
  const nextIds = new Set(busyCardIds.value);
  nextIds[busy ? 'add' : 'delete'](card.id);
  busyCardIds.value = nextIds;
};

const withCardAction = async (card, action) => {
  if (isCardBusy(card)) return false;

  setCardBusy(card, true);
  try {
    return await action();
  } finally {
    setCardBusy(card, false);
  }
};

const cardFields = useKanbanCardFields({
  t,
  boardIdFor: () => boardId.value,
  patchCard: (card, partial) => Object.assign(card, partial),
  resolveLabels: titles =>
    titles.map(
      title =>
        (storeLabels.value || []).find(label => label.title === title) || {
          title,
        }
    ),
  resolveAssignees: ids =>
    ids
      .map(id =>
        assignableUsers.value.find(user => Number(user.id) === Number(id))
      )
      .filter(Boolean),
});

const closeCardDetails = () => {
  selectedCardId.value = null;
};

const exitThen = action => {
  closeCardDetails();
  action?.();
};

const openAddItem = group => {
  addItemStage.value = stages.value.find(stage => stage.id === group.stageId);
};

const closeAddItem = () => {
  addItemStage.value = null;
};

const onManualCardCreated = async () => {
  closeAddItem();
  useAlert(t('KANBAN.ADD_ITEM.CREATE_SUCCESS'));
  await loadList();
};

const moveCardToStage = async (card, targetStageId) => {
  return withCardAction(card, async () => {
    try {
      await KanbanBoardsAPI.reorderCardById(boardId.value, card.id, {
        card: { kanban_stage_id: Number(targetStageId), after_card_id: null },
      });
      await loadList();
      useAlert(t('KANBAN.CARD.MOVE_SUCCESS'));
      return true;
    } catch (error) {
      useAlert(apiErrorMessage(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR')));
      return false;
    }
  });
};

const moveCardToBoard = async (card, { boardId: targetBoardId, stageId }) =>
  withCardAction(card, async () => {
    const targetBoard = boards.value.find(
      item => Number(item.id) === Number(targetBoardId)
    );
    if (!targetBoard) return false;

    try {
      await KanbanBoardsAPI.moveCardToBoard(boardId.value, card.id, {
        target_kanban_board_id: targetBoard.id,
        kanban_stage_id: stageId,
      });
      await loadList();
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_SUCCESS', { board: targetBoard.name })
      );
      return true;
    } catch (error) {
      const errorCode = error?.response?.data?.error;
      let errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR');
      if (errorCode === 'card_already_in_target_board') {
        errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR_DUPLICATE', {
          board: targetBoard.name,
        });
      } else if (errorCode === 'inbox_not_allowed') {
        errorMessage = t('KANBAN.CARD.MOVE_BOARD_ERROR_INBOX', {
          board: targetBoard.name,
        });
      }
      useAlert(errorMessage);
      return false;
    }
  });

const updateCardPriority = (card, priority) =>
  withCardAction(card, async () => {
    const updated = await cardFields.updateDetail(card, 'priority', priority, {
      patchKey: 'cardPriority',
    });
    if (updated) await loadList();
  });

const updateCardDueDate = (card, dueDate) =>
  withCardAction(card, async () => {
    const updated = await cardFields.updateDetail(card, 'dueAt', dueDate);
    if (updated) {
      await loadList();
      useAlert(t('KANBAN.CARD.DUE_DATE_UPDATE_SUCCESS'));
    }
  });

const updateCardLabels = (card, labels) =>
  withCardAction(card, async () => {
    const updated = await cardFields.updateLabels(card, labels);
    if (updated) await loadList();
  });

const assignAgent = (card, userId) =>
  withCardAction(card, async () => {
    const numericUserId = Number(userId);
    const currentIds = (card.assignees || []).map(assignee =>
      Number(assignee.id)
    );
    const nextIds = currentIds.includes(numericUserId)
      ? currentIds.filter(id => id !== numericUserId)
      : [...currentIds, numericUserId];
    const updated = await cardFields.updateAssignees(card, nextIds);
    if (updated) {
      await loadList();
      useAlert(t('KANBAN.CARD.ASSIGN_SUCCESS'));
    }
  });

const onChangeCardStatus = (card, { targetStageId, reasonId, reopen }) =>
  withCardAction(card, async () => {
    try {
      if (reopen) {
        await KanbanBoardsAPI.reopenCardById(boardId.value, card.id);
      } else {
        await KanbanBoardsAPI.updateCardById(boardId.value, card.id, {
          card: {
            kanban_stage_id: targetStageId,
            kanban_reason_id: reasonId || null,
          },
        });
      }
      await loadList();
      useAlert(
        t(
          reopen
            ? 'KANBAN.CARD.STATUS.REOPEN_SUCCESS'
            : 'KANBAN.CARD.STATUS.UPDATE_SUCCESS'
        )
      );
    } catch (error) {
      useAlert(getCardStatusChangeErrorMessage(error, { reopen, t }));
    }
  });

const conversationPath = card =>
  frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: card.conversationId,
    }),
    { card_id: card.id }
  );

const openConversationInNewTab = card => {
  if (!card?.conversationId) return;

  exitThen(() =>
    window.open(
      `${window.chatwootConfig.hostURL}${conversationPath(card)}`,
      '_blank',
      'noopener,noreferrer'
    )
  );
};

const openConversation = (card, event = {}) => {
  if (!card?.conversationId) return;

  if (event.metaKey || event.ctrlKey) {
    openConversationInNewTab(card);
    return;
  }

  exitThen(() =>
    router.push({
      name: 'kanban_board_conversation',
      params: {
        accountId: route.params.accountId,
        boardId: boardId.value,
        conversationId: card.conversationId,
      },
      query: { card_id: card.id, kanban_view: 'list' },
    })
  );
};

const openCardInFunnel = card => {
  exitThen(() =>
    router.push({
      name: 'kanban_board_show',
      params: { accountId: route.params.accountId, boardId: boardId.value },
      query: { card_id: card.id },
    })
  );
};

const copyCardLink = async card => {
  const path = frontendURL(
    `accounts/${route.params.accountId}/kanban/${boardId.value}`,
    { card_id: card.id }
  );
  await copyTextToClipboard(`${window.chatwootConfig.hostURL}${path}`);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_LINK_COPIED'));
};

const onBoardChanged = ({ boardName } = {}) => {
  closeCardDetails();
  loadList();
  useAlert(
    t('KANBAN.CARD.MOVE_BOARD_SUCCESS', {
      board: boardName || t('KANBAN.NO_BOARD_SELECTED'),
    })
  );
};

const openRemoveCardConfirmation = card => {
  closeCardDetails();
  cardPendingRemoval.value = card;
  showRemoveCardConfirmation.value = true;
};

const closeRemoveCardConfirmation = () => {
  showRemoveCardConfirmation.value = false;
  cardPendingRemoval.value = null;
};

const confirmRemoveCard = async () => {
  const card = cardPendingRemoval.value;
  closeRemoveCardConfirmation();
  if (!card) return;

  try {
    await KanbanBoardsAPI.deleteCardById(boardId.value, card.id);
    await loadList();
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_SUCCESS'));
  } catch (error) {
    useAlert(t('KANBAN.ACTIONS.REMOVE_CARD_ERROR'));
  }
};

const cardTitle = card =>
  card.subject || card.contact?.name || t('KANBAN.CARD.UNKNOWN_CONTACT');

watch(searchInput, () => scheduleSearch(runSearch));
watch(groupBy, loadList);
watch(boardId, loadList);

onMounted(loadList);
</script>

<template>
  <KanbanBoardViewShell>
    <div
      class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-4 md:p-6"
      data-testid="kanban-list"
    >
      <div class="flex flex-col gap-2 lg:flex-row lg:items-center">
        <div class="min-w-0 max-w-sm flex-1">
          <Input
            v-model="searchInput"
            type="search"
            size="sm"
            class="group min-w-0 [&>input]:!rounded-[0.625rem] [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
            :placeholder="t('KANBAN.SEARCH.PLACEHOLDER')"
            data-testid="kanban-list-search-input"
            @keydown="onSearchKeydown"
          >
            <template #prefix>
              <Icon
                :icon="
                  isSearchLoading ? 'i-lucide-loader-2' : 'i-lucide-search'
                "
                class="absolute top-1/2 size-3.5 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand ltr:left-2.5 rtl:right-2.5"
                :class="{ 'animate-spin': isSearchLoading }"
              />
            </template>
          </Input>
        </div>

        <div class="flex flex-shrink-0 items-center gap-2 lg:ms-auto">
          <KanbanListGroupBySelect v-model="groupBy" />

          <div
            data-testid="kanban-list-filter-menu-container"
            class="flex flex-shrink-0 items-center overflow-hidden rounded-lg"
            :class="{
              'border border-n-weak bg-n-alpha-1': hasActiveBoardFilters,
            }"
          >
            <KanbanFilterMenu
              :model-value="boardFilters"
              :inbox-options="inboxFilterOptions"
              :agent-options="agentFilterOptions"
              :active-count="activeBoardFilterCount"
              @update:model-value="updateBoardFilters"
            />
            <button
              v-if="hasActiveBoardFilters"
              type="button"
              data-testid="kanban-list-clear-filters"
              class="h-10 border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 ltr:border-l rtl:border-r"
              @click="clearBoardFilters"
            >
              {{ t('KANBAN.FILTERS.CLEAR_ALL') }}
            </button>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-3" :class="{ 'opacity-50': isLoading }">
        <KanbanListGroup
          v-for="group in groups"
          :key="group.key"
          :group="group"
          :board="board"
          :boards="boards"
          :stages="stages"
          :assignable-users="assignableUsers"
          :is-admin="isAdmin"
          :is-card-busy="isCardBusy"
          :can-add-card="canAddCardInGroup(group)"
          :is-loading-more="isGroupLoading(group.key)"
          @open-card="openCard"
          @open-conversation="openConversation"
          @open-conversation-in-new-tab="openConversationInNewTab"
          @remove-card="openRemoveCardConfirmation"
          @update-priority="updateCardPriority"
          @change-status="onChangeCardStatus"
          @move-card-to-stage="moveCardToStage"
          @move-card-to-board="moveCardToBoard"
          @assign-agent="assignAgent"
          @update-due-date="updateCardDueDate"
          @update-labels="updateCardLabels"
          @add-card="openAddItem"
          @load-more="loadMoreForGroup"
        />

        <p
          v-if="board && !groups.length"
          class="p-6 text-center text-sm text-n-slate-11"
          data-testid="kanban-list-empty"
        >
          {{ t('KANBAN.EMPTY_STAGES') }}
        </p>
      </div>
    </div>

    <KanbanOpportunityPanel
      v-if="selectedCardId && board"
      :board-id="boardId"
      :card-id="selectedCardId"
      :board-name="board.name"
      :board="board"
      :boards="boards"
      :stages="stages"
      :won-stage-id="board.wonStageId"
      :lost-stage-id="board.lostStageId"
      :lost-reason-required="!!board.lostReasonRequired"
      :reasons="board.reasons || []"
      :custom-fields="board.customFields || []"
      :move-to-stage="moveCardToStage"
      @close="closeCardDetails"
      @updated="loadList"
      @open-conversation="openConversation"
      @open-conversation-in-new-tab="openConversationInNewTab"
      @open-funnel="openCardInFunnel"
      @copy-card-link="copyCardLink"
      @board-changed="onBoardChanged"
      @remove-card="openRemoveCardConfirmation"
    />

    <woot-modal
      v-if="addItemStage && board"
      show
      :show-close-button="false"
      size="modal-narrow"
      :on-close="closeAddItem"
    >
      <KanbanOpportunityPicker
        :kanban-board-id="boardId"
        :kanban-stage-id="addItemStage.id"
        :kanban-stage-name="addItemStage.name"
        :inbox-scope-mode="board.inboxScopeMode"
        :allowed-inbox-ids="board.allowedInboxIds"
        @created="onManualCardCreated"
        @close="closeAddItem"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showRemoveCardConfirmation"
      :on-close="closeRemoveCardConfirmation"
      :on-confirm="confirmRemoveCard"
      :title="t('KANBAN.REMOVE_CARD.TITLE')"
      :message="t('KANBAN.REMOVE_CARD.MESSAGE')"
      :message-value="cardPendingRemoval ? cardTitle(cardPendingRemoval) : ''"
      :confirm-text="t('KANBAN.REMOVE_CARD.CONFIRM')"
      :reject-text="t('KANBAN.REMOVE_CARD.CANCEL')"
    />
  </KanbanBoardViewShell>
</template>
