<script setup>
import { computed, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getCardStatusChangeErrorMessage,
  isDirectWonLostTransitionError,
} from 'dashboard/helper/kanbanCardStatus';
import { formatDateInput, toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanCardDetailsTab from './tabs/KanbanCardDetailsTab.vue';
import KanbanCardItemsTab from './tabs/KanbanCardItemsTab.vue';
import KanbanCardTimelineTab from './tabs/KanbanCardTimelineTab.vue';
import KanbanCardMoveDialog from '../KanbanCardMoveDialog.vue';
import KanbanOpportunityHeader from './KanbanOpportunityHeader.vue';
import KanbanOpportunitySaveBar from './KanbanOpportunitySaveBar.vue';
import { normalizePayload } from './opportunityPayload';
import { useOpportunityForm } from './composables/useOpportunityForm';
import { useOpportunityQuickActions } from './composables/useOpportunityQuickActions';
import { useOpportunitySave } from './composables/useOpportunitySave';
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

const isAdditionalDataDirty = () =>
  !!additionalDataTabRef.value?.hasUnsavedChanges;

const form = useOpportunityForm({ isAdditionalDataDirty });
const {
  card,
  subject,
  description,
  dueAt,
  priority,
  selectedLabelTitles,
  assignedUsers,
  assignableUsers,
  savedAt,
  savedTimeLabel,
  hasGeneralChanges,
  hasUnsavedChanges,
  unsavedFields,
  patchCard,
} = form;

const {
  isSaving,
  saveError,
  saveCard: persistCard,
} = useOpportunitySave({
  boardId: toRef(props, 'boardId'),
  cardId: toRef(props, 'cardId'),
  form,
  additionalData: {
    isDirty: isAdditionalDataDirty,
    save: () => additionalDataTabRef.value?.saveFieldValues() ?? true,
  },
});

// Bumped on every server side change so views rebuilt from the card, like the
// timeline, remount instead of showing what they fetched before the change.
const cardVersion = ref(0);
const notifyCardUpdated = () => {
  cardVersion.value += 1;
  emit('updated', card.value);
};

const { isPending, run: runQuickAction } = useOpportunityQuickActions({
  patchCard,
  getCard: () => card.value,
  onUpdated: notifyCardUpdated,
});

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

const cardResponse = response => normalizePayload(response?.data);

const onSubjectChanged = subjectValue => {
  const nextSubject = subjectValue.trim();
  const previousSubject = subject.value;
  if (!nextSubject || nextSubject === previousSubject) return false;

  return runQuickAction('subject', {
    optimistic: () => {
      subject.value = nextSubject;
      patchCard({ subject: nextSubject });
    },
    request: () =>
      KanbanBoardsAPI.updateCardDetailsById(props.boardId, props.cardId, {
        subject: nextSubject,
      }),
    revert: () => {
      subject.value = previousSubject;
      patchCard({ subject: previousSubject });
    },
    apply: response => {
      const updated = cardResponse(response);
      const savedSubject = updated.subject ?? nextSubject;
      subject.value = savedSubject;
      return { subject: savedSubject };
    },
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.SUBJECT_UPDATE_ERROR'),
  });
};

const onPriorityChanged = priorityValue => {
  const nextPriority = priorityValue || '';
  const previousPriority = priority.value;

  return runQuickAction('priority', {
    optimistic: () => {
      priority.value = nextPriority;
      patchCard({ priority: nextPriority });
    },
    request: () =>
      KanbanBoardsAPI.updateCardDetailsById(props.boardId, props.cardId, {
        priority: nextPriority || null,
      }),
    revert: () => {
      priority.value = previousPriority;
      patchCard({ priority: previousPriority });
    },
    apply: response => {
      const updated = cardResponse(response);
      const savedPriority = updated.priority ?? nextPriority;
      priority.value = savedPriority || '';
      return { priority: savedPriority || '' };
    },
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'),
  });
};

const onDueAtChanged = dueDate => {
  const nextDueAt = dueDate || '';
  const previousDueAt = dueAt.value;

  return runQuickAction('dueAt', {
    optimistic: () => {
      dueAt.value = nextDueAt;
      patchCard({ dueAt: nextDueAt });
    },
    request: () =>
      KanbanBoardsAPI.updateCardDetailsById(props.boardId, props.cardId, {
        due_at: toIso8601(nextDueAt),
      }),
    revert: () => {
      dueAt.value = previousDueAt;
      patchCard({ dueAt: previousDueAt });
    },
    apply: response => {
      const updated = cardResponse(response);
      const savedDueAt = updated.dueAt ?? nextDueAt;
      dueAt.value = savedDueAt ? formatDateInput(savedDueAt) : '';
      return { dueAt: savedDueAt || '' };
    },
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'),
  });
};

const labelsForTitles = titles =>
  titles.map(
    title =>
      accountLabels.value.find(label => label.title === title) || { title }
  );

const setLabels = titles => {
  selectedLabelTitles.value = [...titles];
  patchCard({ labels: labelsForTitles(titles) });
};

const onLabelsChanged = titles => {
  const nextTitles = [...titles];
  const previousTitles = [...selectedLabelTitles.value];

  return runQuickAction('labels', {
    optimistic: () => setLabels(nextTitles),
    request: () =>
      KanbanBoardsAPI.updateCardLabels(props.boardId, props.cardId, nextTitles),
    revert: () => setLabels(previousTitles),
    apply: response => {
      const responseLabels = normalizePayload(
        response?.data?.payload ?? response?.data ?? []
      );
      const savedLabels = Array.isArray(responseLabels)
        ? responseLabels
        : labelsForTitles(nextTitles);
      const savedTitles = savedLabels
        .map(label => label.title || label)
        .filter(Boolean);
      setLabels(savedTitles);
      return { labels: savedLabels };
    },
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'),
  });
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitles.value.includes(title)) return false;

  return onLabelsChanged([...selectedLabelTitles.value, title]);
};

const onRemoveLabel = title =>
  onLabelsChanged(
    selectedLabelTitles.value.filter(selectedTitle => selectedTitle !== title)
  );

const setAssignedUsers = users => {
  assignedUsers.value = [...users];
  patchCard({ assignees: [...users] });
};

const onToggleAssignee = user => {
  const previousUsers = [...assignedUsers.value];
  const isAssigned = previousUsers.some(
    assignedUser => Number(assignedUser.id) === Number(user.id)
  );
  const nextUsers = isAssigned
    ? previousUsers.filter(
        assignedUser => Number(assignedUser.id) !== Number(user.id)
      )
    : [...previousUsers, user];
  const nextAssigneeIds = nextUsers.map(assignedUser =>
    Number(assignedUser.id)
  );

  return runQuickAction('assignees', {
    optimistic: () => setAssignedUsers(nextUsers),
    request: () =>
      KanbanBoardsAPI.updateCardAssignees(
        props.boardId,
        props.cardId,
        nextAssigneeIds
      ),
    revert: () => setAssignedUsers(previousUsers),
    apply: response => {
      const payload = normalizePayload(response?.data || {});
      const savedUsers = payload.payload || nextUsers;
      assignedUsers.value = savedUsers;
      assignableUsers.value = payload.assignableUsers || assignableUsers.value;
      return {
        assignees: savedUsers,
        assignableUsers: assignableUsers.value,
      };
    },
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'),
  });
};

const moveToStage = (targetCard, targetStageId) => {
  const previousStageId = card.value?.kanbanStageId;

  return runQuickAction('stage', {
    optimistic: () => patchCard({ kanbanStageId: targetStageId }),
    request: () => props.moveToStage(targetCard, Number(targetStageId)),
    revert: () => patchCard({ kanbanStageId: previousStageId }),
    apply: () => ({ kanbanStageId: Number(targetStageId) }),
    errorMessage: t('KANBAN.OPPORTUNITY_DETAILS.QUICK_UPDATE_ERROR'),
  });
};

const isLostReasonRequiredError = error =>
  error?.response?.data?.error === 'lost_reason_required';

const moveStageErrorMessage = error => {
  if (isLostReasonRequiredError(error)) {
    return t('KANBAN.ACTIONS.DRAG_LOST_REASON_REQUIRED');
  }
  if (isDirectWonLostTransitionError(error)) {
    return t('KANBAN.ACTIONS.DRAG_DIRECT_WON_LOST_TRANSITION_NOT_ALLOWED');
  }

  return apiErrorMessage(error, t('KANBAN.ACTIONS.REORDER_CARD_ERROR'));
};

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

  isMovingCard.value = true;

  try {
    if (sourceBoardId === targetBoardId) {
      await KanbanBoardsAPI.reorderCardById(sourceBoardId, card.value.id, {
        card: {
          kanban_stage_id: targetStageId,
          after_card_id: null,
        },
      });
      patchCard({ kanbanStageId: targetStageId });
      notifyCardUpdated();
      showMoveDialog.value = false;
      useAlert(t('KANBAN.CARD.MOVE_SUCCESS'));
      return;
    }

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
    if (sourceBoardId === targetBoardId) {
      useAlert(moveStageErrorMessage(error));
      return;
    }

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
  const previousReasonId = card.value?.kanbanReasonId;
  const nextReasonId = reopen ? null : reasonId || null;

  const changed = await runQuickAction('status', {
    optimistic: () =>
      patchCard({
        ...(reopen ? {} : { kanbanStageId: targetStageId }),
        kanbanReasonId: nextReasonId,
      }),
    request: () =>
      reopen
        ? KanbanBoardsAPI.reopenCardById(props.boardId, props.cardId)
        : KanbanBoardsAPI.updateCardById(props.boardId, props.cardId, {
            card: {
              kanban_stage_id: targetStageId,
              kanban_reason_id: nextReasonId,
            },
          }),
    revert: () =>
      patchCard({
        kanbanStageId: previousStageId,
        kanbanReasonId: previousReasonId,
      }),
    apply: response => {
      const updated = cardResponse(response);
      return {
        kanbanStageId:
          updated.kanbanStageId ?? (reopen ? previousStageId : targetStageId),
        kanbanReasonId: updated.kanbanReasonId ?? nextReasonId,
      };
    },
    errorMessage: error =>
      getCardStatusChangeErrorMessage(error, { reopen, t }),
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
    label: `${t('KANBAN.OPPORTUNITY_DETAILS.TABS.DETAILS')}${
      hasGeneralChanges.value ? ' •' : ''
    }`,
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
    form.setFormState(cardPayload);
    form.setEmbeddedContext(cardPayload);
    form.captureSnapshot();
  } catch (error) {
    loadError.value = apiErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const saveCard = async () => {
  const saved = await persistCard();
  if (saved) notifyCardUpdated();

  return saved;
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
  onSave: saveCard,
  onClose: () => emit('close'),
});

onMounted(loadCard);

defineExpose({
  saveCard,
  hasUnsavedChanges,
  unsavedFields,
});
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
        :has-unsaved-changes="hasUnsavedChanges"
        :is-pending="isPending"
        :subject="subject"
        :priority="priority"
        :due-at="dueAt"
        :stages="stages"
        :won-stage-id="wonStageId"
        :lost-stage-id="lostStageId"
        :lost-reason-required="lostReasonRequired"
        :reasons="reasons"
        :move-to-stage="moveToStage"
        :account-labels="accountLabels"
        :selected-label-titles="selectedLabelTitles"
        :assigned-users="assignedUsers"
        :assignable-users="assignableUsers"
        :total-value="totalValue"
        @update:subject="onSubjectChanged"
        @update:priority="onPriorityChanged"
        @update:due-at="onDueAtChanged"
        @change-status="onChangeCardStatus"
        @stage-moved="patchCard({ kanbanStageId: $event })"
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
                <form
                  data-testid="kanban-opportunity-form"
                  class="grid gap-5"
                  @submit.prevent="saveCard"
                >
                  <KanbanCardDetailsTab
                    ref="additionalDataTabRef"
                    v-model:description="description"
                    :board-id="boardId"
                    :card-id="cardId"
                    :custom-fields="customFields"
                  />
                </form>
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
          <p
            v-if="saveError"
            data-testid="kanban-opportunity-save-error"
            class="mb-0 mt-4 text-sm text-n-ruby-11"
          >
            {{ saveError }}
          </p>
        </template>
      </div>

      <KanbanOpportunitySaveBar
        :is-saving="isSaving"
        :has-unsaved-changes="hasUnsavedChanges"
        :saved-at="savedAt"
        :saved-time-label="savedTimeLabel"
        @save="saveCard"
        @close="emit('close')"
      />
    </aside>
  </div>
</template>
