<script setup>
import { computed, onMounted, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import KanbanCardAdditionalDataTab from '../KanbanCardAdditionalDataTab.vue';
import KanbanCardOverviewTab from './tabs/KanbanCardOverviewTab.vue';
import KanbanCardItemsTab from './tabs/KanbanCardItemsTab.vue';
import KanbanCardTimelineTab from './KanbanCardTimelineTab.vue';
import KanbanCardContextRail from './KanbanCardContextRail.vue';
import KanbanOpportunityHeader from './KanbanOpportunityHeader.vue';
import KanbanOpportunitySaveBar from './KanbanOpportunitySaveBar.vue';
import { normalizePayload } from './opportunityPayload';
import { useOpportunityForm } from './composables/useOpportunityForm';
import { useOpportunitySave } from './composables/useOpportunitySave';
import { usePanelKeyboard } from './composables/usePanelKeyboard';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
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
});

const emit = defineEmits([
  'close',
  'updated',
  'openConversation',
  'removeCard',
]);

const { t } = useI18n();
const accountLabels = useMapGetter('labels/getLabels');

const panelRef = ref(null);
const additionalDataTabRef = ref(null);
const activeTabKey = ref('general');
const loadedTabKeys = ref(['general']);
const isLoading = ref(false);
const loadError = ref('');
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
  dirtyFields,
  hasGeneralChanges,
  hasUnsavedChanges,
  unsavedFields,
  patchCard,
  addLabel,
  removeLabel,
  toggleAssignee,
} = form;

const {
  isSaving,
  saveError,
  subjectError,
  saveCard: persistCard,
} = useOpportunitySave({
  boardId: toRef(props, 'boardId'),
  cardId: toRef(props, 'cardId'),
  form,
  additionalData: {
    isDirty: isAdditionalDataDirty,
    save: () => additionalDataTabRef.value.saveFieldValues(),
  },
});

// Bumped on every server side change so views rebuilt from the card, like the
// timeline, remount instead of showing what they fetched before the change.
const cardVersion = ref(0);
const notifyCardUpdated = () => {
  cardVersion.value += 1;
  emit('updated', card.value);
};

const cardDisplayId = computed(() => card.value?.id || props.cardId);
const totalValue = computed(
  () => productsTotalValue.value ?? Number(card.value?.value || 0)
);

const tabItems = computed(() => [
  {
    key: 'general',
    label: `${t('KANBAN.OPPORTUNITY_DETAILS.TABS.GENERAL')}${
      hasGeneralChanges.value ? ' •' : ''
    }`,
  },
  { key: 'products', label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS') },
  {
    key: 'additionalData',
    label: `${t('KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA')}${
      dirtyFields.value.additionalData ? ' •' : ''
    }`,
  },
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

const getErrorMessage = (error, fallback) => {
  const errors = error?.response?.data?.errors;

  if (Array.isArray(errors)) return errors.join(', ');
  if (typeof errors === 'string') return errors;
  if (errors && typeof errors === 'object') {
    return Object.values(errors).flat().join(', ');
  }

  return error?.response?.data?.message || error?.message || fallback;
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
    loadError.value = getErrorMessage(
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

const onChangeCardStatus = async ({ targetStageId, reasonId, reopen }) => {
  try {
    const response = reopen
      ? await KanbanBoardsAPI.reopenCardById(props.boardId, props.cardId)
      : await KanbanBoardsAPI.updateCardById(props.boardId, props.cardId, {
          card: {
            kanban_stage_id: targetStageId,
            kanban_reason_id: reasonId || null,
          },
        });
    const updatedCard = normalizePayload(response.data);

    // Only the stage and the reason are applied: pending edits stay pending.
    patchCard({
      kanbanStageId:
        updatedCard.kanbanStageId ??
        (reopen ? card.value?.kanbanStageId : targetStageId),
      kanbanReasonId:
        updatedCard.kanbanReasonId ?? (reopen ? null : reasonId || null),
    });
    notifyCardUpdated();
    useAlert(
      t(
        reopen
          ? 'KANBAN.CARD.STATUS.REOPEN_SUCCESS'
          : 'KANBAN.CARD.STATUS.UPDATE_SUCCESS'
      )
    );
  } catch (error) {
    useAlert(
      getCardStatusChangeErrorMessage(error, { reopen, t, getErrorMessage })
    );
  }
};

const copyCardId = async () => {
  await copyTextToClipboard(cardDisplayId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const openConversation = () => {
  if (card.value?.conversationId) emit('openConversation', card.value);
};

usePanelKeyboard({
  panelRef,
  isBlocked: () => props.hasBlockingDialog,
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
      class="flex h-full w-full max-w-full flex-col overflow-hidden border-n-weak bg-n-background shadow-xl outline-none ltr:ml-auto ltr:border-l rtl:mr-auto rtl:border-r md:w-[min(56rem,70vw)]"
    >
      <KanbanOpportunityHeader
        :card="card"
        :card-display-id="cardDisplayId"
        :has-unsaved-changes="hasUnsavedChanges"
        :stages="stages"
        :won-stage-id="wonStageId"
        :lost-stage-id="lostStageId"
        :lost-reason-required="lostReasonRequired"
        :reasons="reasons"
        :move-to-stage="moveToStage"
        @change-status="onChangeCardStatus"
        @stage-moved="patchCard({ kanbanStageId: $event })"
        @copy-card-id="copyCardId"
        @remove-card="emit('removeCard', $event)"
        @close="emit('close')"
      />

      <div class="flex-none border-b border-n-weak px-4 py-3">
        <TabBar
          :tabs="tabItems"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <div class="min-h-0 flex-1 overflow-auto px-4 py-4">
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
          <div
            data-testid="kanban-opportunity-layout"
            class="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(16rem,18rem)]"
          >
            <div class="min-w-0">
              <section
                v-show="activeTabKey === 'general'"
                data-testid="kanban-opportunity-general-tab"
              >
                <form
                  data-testid="kanban-opportunity-form"
                  class="grid gap-5"
                  @submit.prevent="saveCard"
                >
                  <KanbanCardOverviewTab
                    v-model:subject="subject"
                    v-model:description="description"
                    v-model:priority="priority"
                    :subject-error="subjectError"
                    @clear-subject-error="subjectError = ''"
                  />
                </form>
              </section>

              <KanbanCardItemsTab
                v-if="loadedTabKeys.includes('products')"
                v-show="activeTabKey === 'products'"
                :board-id="boardId"
                :card-id="cardId"
                @total-changed="productsTotalValue = $event"
              />
              <section
                v-if="loadedTabKeys.includes('additionalData')"
                v-show="activeTabKey === 'additionalData'"
                data-testid="kanban-opportunity-additional-data-tab"
              >
                <KanbanCardAdditionalDataTab
                  ref="additionalDataTabRef"
                  :board-id="boardId"
                  :card-id="cardId"
                  :custom-fields="customFields"
                />
              </section>
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

            <KanbanCardContextRail
              v-model:due-at="dueAt"
              :card="card"
              :account-labels="accountLabels"
              :selected-label-titles="selectedLabelTitles"
              :assigned-users="assignedUsers"
              :assignable-users="assignableUsers"
              :total-value="totalValue"
              @add-label="addLabel"
              @remove-label="removeLabel"
              @toggle-assignee="toggleAssignee"
              @open-conversation="openConversation"
            />
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
