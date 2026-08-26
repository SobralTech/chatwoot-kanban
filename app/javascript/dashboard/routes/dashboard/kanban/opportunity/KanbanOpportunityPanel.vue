<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useKanbanCardFields } from 'dashboard/composables/useKanbanCardFields';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';
import { formatDateInput } from 'dashboard/helper/kanbanDueDate';
import { isLostReasonRequiredError } from 'dashboard/helper/kanbanStageError';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanCardDetailsTab from './tabs/KanbanCardDetailsTab.vue';
import KanbanCardItemsTab from './tabs/KanbanCardItemsTab.vue';
import KanbanCardTimelineTab from './tabs/KanbanCardTimelineTab.vue';
import KanbanCardMoveDialog from '../KanbanCardMoveDialog.vue';
import KanbanOpportunityHeader from './KanbanOpportunityHeader.vue';
import { normalizePayload } from './opportunityPayload';
import { usePanelKeyboard } from './composables/usePanelKeyboard';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
  boardName: {
    type: String,
    default: '',
  },
  board: {
    type: Object,
    default: () => ({}),
  },
  boards: {
    type: Array,
    default: () => [],
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  lostStageId: {
    type: Number,
    default: null,
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  customFields: {
    type: Array,
    default: () => [],
  },
  stages: {
    type: Array,
    default: () => [],
  },
  moveToStage: {
    type: Function,
    required: true,
  },
  // A dialog stacked above the panel owns the keyboard while it is open.
  hasBlockingDialog: {
    type: Boolean,
    default: false,
  },
  openedFromConversation: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'close',
  'updated',
  'openConversation',
  'openConversationInNewTab',
  'openFunnel',
  'copyCardLink',
  'removeCard',
  'boardChanged',
]);

// Long enough that typing a sentence is one save, short enough that the value
// is on the server before the user moves on.
const DESCRIPTION_SAVE_DELAY = 800;

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');

const panelRef = ref(null);
const additionalDataTabRef = ref(null);
const activeTabKey = ref('details');
const loadedTabKeys = ref(['details']);
const isLoading = ref(false);
const loadError = ref('');
const showMoveDialog = ref(false);
const isMovingCard = ref(false);
const productsTotalValue = ref(null);

const card = ref(null);
const description = ref('');
const assignableUsers = ref([]);

const patchCard = partial => {
  card.value = { ...(card.value || {}), ...partial };
};

// The header edits these straight through the card: they persist on change, so
// mirroring them into their own refs only created two things to keep in sync.
const subject = computed(() => card.value?.subject || '');
const priority = computed(() => card.value?.priority || '');
const dueAt = computed(() => formatDateInput(card.value?.dueAt));
const selectedLabelTitles = computed(() =>
  (card.value?.labels || []).map(label => label.title || label).filter(Boolean)
);
const assignedUsers = computed(() => card.value?.assignees || []);

// Bumped on every server side change so views rebuilt from the card, like the
// timeline, remount instead of showing what they fetched before the change.
const cardVersion = ref(0);
const notifyCardUpdated = () => {
  cardVersion.value += 1;
  emit('updated', card.value);
};

const {
  isPending: isCardFieldPending,
  run: runQuickAction,
  updateDetail,
  updateLabels,
  updateAssignees,
} = useKanbanCardFields({
  t,
  boardIdFor: () => Number(props.boardId),
  patchCard: (targetCard, partial) => patchCard(partial),
  onUpdated: notifyCardUpdated,
  onAssignableUsers: (targetCard, users) => {
    assignableUsers.value = users;
  },
  resolveLabels: titles =>
    titles.map(
      title =>
        accountLabels.value.find(label => label.title === title) || { title }
    ),
  resolveAssignees: ids =>
    ids.map(
      id =>
        assignedUsers.value.find(user => Number(user.id) === Number(id)) ||
        assignableUsers.value.find(user => Number(user.id) === Number(id)) || {
          id,
        }
    ),
});

// The header only ever asks about the card the panel is showing.
const isPending = field => isCardFieldPending(card.value, field);

// The description is the last field that used to wait for a save button. It now
// persists once typing settles, which is what let the whole draft apparatus go.
const saveDescription = () => {
  if (!card.value || description.value === (card.value.description || '')) {
    return false;
  }

  return updateDetail(card.value, 'description', description.value);
};
let descriptionSaveTimer = null;
const queueDescriptionSave = () => {
  clearTimeout(descriptionSaveTimer);
  descriptionSaveTimer = setTimeout(saveDescription, DESCRIPTION_SAVE_DELAY);
};

// Anything still queued is sent now, and nothing stays armed behind it: a timer
// that outlives the panel would fire a save for a card nobody is looking at.
const flushPendingSaves = () => {
  clearTimeout(descriptionSaveTimer);
  saveDescription();
  additionalDataTabRef.value?.saveFieldValues();
};

onBeforeUnmount(flushPendingSaves);

const isSaving = computed(
  () => isPending('description') || !!additionalDataTabRef.value?.isSavingFields
);

const cardDisplayId = computed(() => card.value?.id || props.cardId);
const totalValue = computed(
  () => productsTotalValue.value ?? Number(card.value?.value || 0)
);
const moveBoard = computed(() =>
  props.board?.id
    ? props.board
    : {
        id: Number(props.boardId),
        name: props.boardName,
        stages: props.stages,
        wonStageId: props.wonStageId,
        lostStageId: props.lostStageId,
        customFields: props.customFields,
      }
);
const moveBoards = computed(() =>
  props.boards.length ? props.boards : [moveBoard.value]
);
const cardInboxId = computed(
  () =>
    card.value?.inboxId ??
    card.value?.inbox?.id ??
    card.value?.conversation?.inboxId ??
    null
);

const onProductsTotalChanged = value => {
  productsTotalValue.value = value;
};

const onProductsCardChanged = updatedCard => {
  patchCard(updatedCard);
  productsTotalValue.value = Number(updatedCard.value ?? 0);
  notifyCardUpdated();
};

const onSubjectChanged = subjectValue => {
  const nextSubject = subjectValue.trim();
  if (!nextSubject || nextSubject === subject.value) return false;

  return updateDetail(card.value, 'subject', nextSubject);
};

const onPriorityChanged = value =>
  updateDetail(card.value, 'priority', value || '');

const onDueAtChanged = value => updateDetail(card.value, 'dueAt', value || '');

const onLabelsChanged = titles => updateLabels(card.value, titles);

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitles.value.includes(title)) return false;

  return onLabelsChanged([...selectedLabelTitles.value, title]);
};

const onRemoveLabel = title =>
  onLabelsChanged(
    selectedLabelTitles.value.filter(selectedTitle => selectedTitle !== title)
  );

const onToggleAssignee = user => {
  const assignedIds = assignedUsers.value.map(assigned => Number(assigned.id));
  const nextIds = assignedIds.includes(Number(user.id))
    ? assignedIds.filter(id => id !== Number(user.id))
    : [...assignedIds, Number(user.id)];

  return updateAssignees(card.value, nextIds);
};

const moveStageErrorMessage = error => {
  if (isLostReasonRequiredError(error)) {
    return t('KANBAN.ACTIONS.DRAG_LOST_REASON_REQUIRED');
  }
  if (isDirectWonLostTransitionError(error)) {
    return t('KANBAN.ACTIONS.DRAG_DIRECT_WON_LOST_TRANSITION_NOT_ALLOWED');
  }

  return apiErrorMessage(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
};

const moveToStage = (targetCard, targetStageId) =>
  runQuickAction(card.value, 'stage', {
    optimistic: { kanbanStageId: Number(targetStageId) },
    request: () => props.moveToStage(targetCard, Number(targetStageId)),
    apply: () => ({ kanbanStageId: Number(targetStageId) }),
    errorKey: moveStageErrorMessage,
  });

const closeMoveDialog = () => {
  if (isMovingCard.value) return;

  showMoveDialog.value = false;
};

const onMoveRequested = async ({ boardId, stageId }) => {
  if (isMovingCard.value || !card.value?.id) return;

  const sourceBoardId = Number(props.boardId);
  const targetBoardId = Number(boardId);
  const targetStageId = Number(stageId);
  const targetBoard = moveBoards.value.find(
    item => Number(item.id) === targetBoardId
  );
  if (!sourceBoardId || !targetBoardId || !targetStageId || !targetBoard)
    return;

  if (sourceBoardId === targetBoardId) {
    isMovingCard.value = true;
    const moved = await moveToStage(card.value, targetStageId);
    isMovingCard.value = false;
    if (moved) {
      showMoveDialog.value = false;
      useAlert(t('KANBAN.CARD.MOVE_SUCCESS'));
    }

    return;
  }

  isMovingCard.value = true;

  try {
    await KanbanBoardsAPI.moveCardToBoard(sourceBoardId, card.value.id, {
      target_kanban_board_id: targetBoardId,
      kanban_stage_id: targetStageId,
    });
    showMoveDialog.value = false;
    emit('boardChanged', {
      boardId: targetBoardId,
      boardName: targetBoard.name,
    });
  } catch (error) {
    const errorCode = error?.response?.data?.error;
    if (errorCode === 'card_already_in_target_board') {
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_ERROR_DUPLICATE', {
          board: targetBoard.name,
        })
      );
    } else if (errorCode === 'inbox_not_allowed') {
      useAlert(
        t('KANBAN.CARD.MOVE_BOARD_ERROR_INBOX', {
          board: targetBoard.name,
        })
      );
    } else {
      useAlert(t('KANBAN.CARD.MOVE_BOARD_ERROR'));
    }
  } finally {
    isMovingCard.value = false;
  }
};

const onChangeCardStatus = async ({ targetStageId, reasonId, reopen }) => {
  const previousStageId = card.value?.kanbanStageId;
  const nextReasonId = reopen ? null : reasonId || null;

  const changed = await runQuickAction(card.value, 'status', {
    optimistic: {
      kanbanStageId: reopen ? previousStageId : targetStageId,
      kanbanReasonId: nextReasonId,
    },
    request: () =>
      reopen
        ? KanbanBoardsAPI.reopenCardById(props.boardId, props.cardId)
        : KanbanBoardsAPI.updateCardById(props.boardId, props.cardId, {
            card: {
              kanban_stage_id: targetStageId,
              kanban_reason_id: nextReasonId,
            },
          }),
    apply: response => {
      const updated = normalizePayload(response?.data);
      return {
        kanbanStageId:
          updated.kanbanStageId ?? (reopen ? previousStageId : targetStageId),
        kanbanReasonId: updated.kanbanReasonId ?? nextReasonId,
      };
    },
    errorKey: error => getCardStatusChangeErrorMessage(error, { reopen, t }),
  });

  if (changed) {
    useAlert(
      t(
        reopen
          ? 'KANBAN.CARD.STATUS.REOPEN_SUCCESS'
          : 'KANBAN.CARD.STATUS.UPDATE_SUCCESS'
      )
    );
  }

  return changed;
};

const openProducts = () => {
  activeTabKey.value = 'products';
  loadedTabKeys.value = [...new Set([...loadedTabKeys.value, 'products'])];
};

const tabItems = computed(() => [
  {
    key: 'details',
    label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.DETAILS'),
  },
  { key: 'products', label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS') },
  {
    key: 'activity',
    label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.ACTIVITY'),
  },
]);
const activeTabIndex = computed(() =>
  tabItems.value.findIndex(tab => tab.key === activeTabKey.value)
);

const onTabChanged = tab => {
  activeTabKey.value = tab.key;
  loadedTabKeys.value = [...new Set([...loadedTabKeys.value, tab.key])];
};

const loadCard = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.showCardById(
      props.boardId,
      props.cardId
    );
    const cardPayload = normalizePayload(response.data);
    card.value = cardPayload;
    description.value = cardPayload.description || '';
    assignableUsers.value = cardPayload.assignableUsers || [];
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const copyCardId = async () => {
  await copyTextToClipboard(cardDisplayId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const openConversation = () => {
  if (card.value?.conversationId) emit('openConversation', card.value);
};

const openConversationInNewTab = () => {
  if (card.value?.conversationId) {
    emit('openConversationInNewTab', card.value);
  }
};

const openFunnel = () => {
  if (card.value?.id) emit('openFunnel', card.value);
};

const copyCardLink = () => {
  if (card.value?.id) emit('copyCardLink', card.value);
};

usePanelKeyboard({
  panelRef,
  isBlocked: () => props.hasBlockingDialog || showMoveDialog.value,
  // Ctrl+S is reflex, not need: it just stops waiting for the debounce.
  onSave: flushPendingSaves,
  onClose: () => emit('close'),
});

onMounted(loadCard);
</script>

<template>
  <div
    data-testid="kanban-opportunity-panel-overlay"
    class="fixed inset-0 z-[9990] flex bg-n-alpha-black2 backdrop-blur-[4px]"
    @mousedown.self="emit('close')"
  >
    <aside
      ref="panelRef"
      data-testid="kanban-opportunity-panel"
      role="dialog"
      aria-modal="true"
      aria-labelledby="kanban-opportunity-title"
      tabindex="-1"
      class="relative flex h-full w-full max-w-full flex-col overflow-hidden border-n-weak bg-n-background shadow-xl outline-none ltr:ml-auto ltr:border-l rtl:mr-auto rtl:border-r md:w-[min(40rem,100vw)]"
    >
      <KanbanOpportunityHeader
        :card="card"
        :card-display-id="cardDisplayId"
        :board-name="boardName"
        :opened-from-conversation="openedFromConversation"
        :is-saving="isSaving"
        :is-pending="isPending"
        :subject="subject"
        :priority="priority"
        :due-at="dueAt"
        :stages="stages"
        :won-stage-id="wonStageId"
        :lost-stage-id="lostStageId"
        :lost-reason-required="lostReasonRequired"
        :reasons="reasons"
        :account-labels="accountLabels"
        :selected-label-titles="selectedLabelTitles"
        :assigned-users="assignedUsers"
        :assignable-users="assignableUsers"
        :total-value="totalValue"
        @update:subject="onSubjectChanged"
        @update:priority="onPriorityChanged"
        @update:due-at="onDueAtChanged"
        @change-status="onChangeCardStatus"
        @copy-card-id="copyCardId"
        @copy-card-link="copyCardLink"
        @add-label="onAddLabel"
        @remove-label="onRemoveLabel"
        @toggle-assignee="onToggleAssignee"
        @open-products="openProducts"
        @open-conversation="openConversation"
        @open-conversation-in-new-tab="openConversationInNewTab"
        @open-funnel="openFunnel"
        @open-move="showMoveDialog = true"
        @remove-card="emit('removeCard', $event)"
        @close="emit('close')"
      />

      <KanbanCardMoveDialog
        v-if="showMoveDialog && card"
        :card="card"
        :boards="moveBoards"
        :board="moveBoard"
        :stages="stages"
        :won-stage-id="wonStageId"
        :lost-stage-id="lostStageId"
        :inbox-id="cardInboxId"
        :reasons="reasons"
        :is-moving="isMovingCard"
        @move="onMoveRequested"
        @close="closeMoveDialog"
      />

      <div class="flex-none border-b border-n-weak px-4 py-3">
        <TabBar
          :tabs="tabItems"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto px-4 py-4">
        <p
          v-if="isLoading"
          data-testid="kanban-opportunity-loading"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.LOADING') }}
        </p>

        <p
          v-else-if="loadError"
          data-testid="kanban-opportunity-load-error"
          class="mb-0 text-sm text-n-ruby-11"
        >
          {{ loadError }}
        </p>

        <template v-else-if="card">
          <div data-testid="kanban-opportunity-layout" class="min-w-0">
            <div class="min-w-0">
              <section
                v-show="activeTabKey === 'details'"
                data-testid="kanban-opportunity-details-tab"
              >
                <KanbanCardDetailsTab
                  ref="additionalDataTabRef"
                  v-model:description="description"
                  data-testid="kanban-opportunity-form"
                  :board-id="boardId"
                  :card-id="cardId"
                  :custom-fields="customFields"
                  @update:description="queueDescriptionSave"
                />
              </section>

              <KanbanCardItemsTab
                v-if="loadedTabKeys.includes('products')"
                v-show="activeTabKey === 'products'"
                :board-id="boardId"
                :card-id="cardId"
                :discount-type="card.discountType"
                :discount-amount="card.discountAmount"
                @total-changed="onProductsTotalChanged"
                @card-changed="onProductsCardChanged"
              />
              <!-- Mounted on demand instead of kept alive: the timeline holds no
              editable state, so remounting on every visit and on every card
              change is all it takes to keep it fresh. -->
              <KanbanCardTimelineTab
                v-if="activeTabKey === 'activity'"
                :key="cardVersion"
                :board-id="boardId"
                :card-id="cardId"
              />
            </div>
          </div>
        </template>
      </div>
    </aside>
  </div>
</template>
