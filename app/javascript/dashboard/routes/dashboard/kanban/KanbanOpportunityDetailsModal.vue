<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import ProductsAPI from 'dashboard/api/products';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { getCardStatusChangeErrorMessage } from 'dashboard/helper/kanbanCardStatus';
import { formatDateInput, toIso8601 } from 'dashboard/helper/kanbanDueDate';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { debounce } from '@chatwoot/utils';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import KanbanDueDatePicker from './KanbanDueDatePicker.vue';
import KanbanPriorityDropdown from './KanbanPriorityDropdown.vue';
import KanbanCardAdditionalDataTab from './KanbanCardAdditionalDataTab.vue';
import KanbanCardStatusBadge from './KanbanCardStatusBadge.vue';

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
});

const emit = defineEmits([
  'close',
  'updated',
  'openConversation',
  'removeCard',
]);

const TAB_KEYS = ['general', 'products', 'additional_data'];

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();
const accountLabels = useMapGetter('labels/getLabels');

const activeTabIndex = ref(0);
const tabItems = computed(() => [
  { label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.GENERAL') },
  { label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.PRODUCTS') },
  { label: t('KANBAN.OPPORTUNITY_DETAILS.TABS.ADDITIONAL_DATA') },
]);
const activeTabKey = computed(() => TAB_KEYS[activeTabIndex.value]);
const onTabChanged = tab => {
  const index = tabItems.value.findIndex(item => item.label === tab.label);
  if (index !== -1) activeTabIndex.value = index;
};

const card = ref(null);
const subject = ref('');
const description = ref('');
const dueAt = ref('');
const priority = ref('');
const isLoading = ref(false);
const isSaving = ref(false);
const isLoadingLabels = ref(false);
const isLoadingAssignees = ref(false);
const loadError = ref('');
const saveError = ref('');
const labelsLoadError = ref('');
const assigneesLoadError = ref('');
const subjectError = ref('');
const selectedLabelTitles = ref([]);
const assignedUsers = ref([]);
const assignableUsers = ref([]);

const cardDisplayId = computed(() => card.value?.id || props.cardId);
const hasConversation = computed(() => !!card.value?.conversationId);
const inboxObject = computed(
  () => card.value?.inbox || card.value?.conversation?.inbox || null
);
const inboxName = computed(
  () => inboxObject.value?.name || t('KANBAN.OPPORTUNITY_DETAILS.NO_INBOX')
);
const selectedAssigneeIds = computed(() =>
  assignedUsers.value.map(user => user.id)
);
const assigneesSummary = computed(() => {
  if (!assignedUsers.value.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED');
  }

  return assignedUsers.value.map(user => user.name).join(', ');
});
const hasContact = computed(() => !!card.value?.contact);
const contactName = computed(
  () =>
    card.value?.contact?.name ||
    card.value?.contact?.email ||
    card.value?.contact?.phone_number ||
    t('KANBAN.OPPORTUNITY_DETAILS.NO_CONTACT')
);
const selectedLabelTitleSet = computed(
  () => new Set(selectedLabelTitles.value)
);
const selectedLabels = computed(() =>
  selectedLabelTitles.value.map(title => {
    const accountLabel = accountLabels.value.find(
      label => label.title === title
    );
    return accountLabel || { title };
  })
);
const selectedLabelsSummary = computed(() => {
  if (!selectedLabelTitles.value.length) {
    return t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED');
  }

  return selectedLabelTitles.value.join(', ');
});

const additionalDataTabRef = ref(null);

const savedSnapshot = ref('');
const buildSnapshot = () =>
  JSON.stringify({
    subject: subject.value,
    description: description.value,
    dueAt: dueAt.value,
    priority: priority.value,
    labels: [...selectedLabelTitles.value].sort(),
    assigneeIds: selectedAssigneeIds.value.slice().sort((a, b) => a - b),
  });
const captureSnapshot = () => {
  savedSnapshot.value = buildSnapshot();
};
const hasUnsavedChanges = computed(
  () =>
    (!!card.value && buildSnapshot() !== savedSnapshot.value) ||
    !!additionalDataTabRef.value?.hasUnsavedChanges
);

const normalizeCard = payload => ({
  ...payload,
  accountId: payload.accountId ?? payload.account_id,
  kanbanBoardId: payload.kanbanBoardId ?? payload.kanban_board_id,
  kanbanStageId: payload.kanbanStageId ?? payload.kanban_stage_id,
  conversationId: payload.conversationId ?? payload.conversation_id,
  dueAt: payload.dueAt ?? payload.due_at,
});

const getErrorMessage = (error, fallback) => {
  const errors = error?.response?.data?.errors;

  if (Array.isArray(errors)) return errors.join(', ');
  if (typeof errors === 'string') return errors;
  if (errors && typeof errors === 'object') {
    return Object.values(errors).flat().join(', ');
  }

  return error?.response?.data?.message || error?.message || fallback;
};

const setFormState = payload => {
  card.value = normalizeCard(payload);
  subject.value = card.value.subject || '';
  description.value = card.value.description || '';
  dueAt.value = formatDateInput(card.value.dueAt);
  priority.value = card.value.priority || '';
};

const getLabelsPayload = response =>
  response?.data?.payload || response?.data || [];

const loadLabels = async () => {
  isLoadingLabels.value = true;
  labelsLoadError.value = '';

  try {
    const [assignedLabelsResponse] = await Promise.all([
      KanbanBoardsAPI.getCardLabels(props.boardId, props.cardId),
      store.dispatch('labels/get'),
    ]);
    selectedLabelTitles.value = getLabelsPayload(assignedLabelsResponse).map(
      label => label.title || label
    );
  } catch (error) {
    labelsLoadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_LABELS_ERROR')
    );
  } finally {
    isLoadingLabels.value = false;
  }
};

const loadAssignees = async () => {
  isLoadingAssignees.value = true;
  assigneesLoadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getCardAssignees(
      props.boardId,
      props.cardId
    );
    assignedUsers.value = response?.data?.payload || [];
    assignableUsers.value = response?.data?.assignable_users || [];
  } catch (error) {
    assigneesLoadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ASSIGNEES_ERROR')
    );
  } finally {
    isLoadingAssignees.value = false;
  }
};

const onToggleAssignee = user => {
  assignedUsers.value = selectedAssigneeIds.value.includes(user.id)
    ? assignedUsers.value.filter(existing => existing.id !== user.id)
    : [...assignedUsers.value, user];
};

const loadCard = async () => {
  isLoading.value = true;
  loadError.value = '';

  try {
    const response = await KanbanBoardsAPI.showCardById(
      props.boardId,
      props.cardId
    );
    setFormState(response.data || {});
  } catch (error) {
    loadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
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
    const updatedCard = normalizeCard(response.data || {});
    setFormState(updatedCard);
    captureSnapshot();
    emit('updated', updatedCard);
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

const saveCard = async () => {
  if (isSaving.value) return false;

  const trimmedSubject = subject.value.trim();
  subjectError.value = '';
  saveError.value = '';

  if (!trimmedSubject) {
    subjectError.value = t('KANBAN.OPPORTUNITY_DETAILS.REQUIRED_TITLE');
    return false;
  }

  isSaving.value = true;

  try {
    const payload = {
      subject: trimmedSubject,
      description: description.value.trim() ? description.value : null,
      due_at: toIso8601(dueAt.value),
      priority: priority.value || null,
    };
    const [cardResponse, labelsResponse, assigneesResponse] = await Promise.all(
      [
        KanbanBoardsAPI.updateCardDetailsById(
          props.boardId,
          props.cardId,
          payload
        ),
        KanbanBoardsAPI.updateCardLabels(
          props.boardId,
          props.cardId,
          selectedLabelTitles.value
        ),
        KanbanBoardsAPI.updateCardAssignees(
          props.boardId,
          props.cardId,
          selectedAssigneeIds.value
        ),
      ]
    );

    const updatedCard = normalizeCard(cardResponse.data || {});
    setFormState(updatedCard);
    selectedLabelTitles.value = getLabelsPayload(labelsResponse).map(
      label => label.title || label
    );
    assignedUsers.value = assigneesResponse?.data?.payload || [];
    assignableUsers.value =
      assigneesResponse?.data?.assignable_users || assignableUsers.value;

    captureSnapshot();

    if (additionalDataTabRef.value?.hasUnsavedChanges) {
      const additionalDataSaved =
        await additionalDataTabRef.value.saveFieldValues();
      if (!additionalDataSaved) return false;
    }

    emit('updated', updatedCard);
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.SAVE_SUCCESS'));
    return true;
  } catch (error) {
    saveError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.SAVE_ERROR')
    );
    return false;
  } finally {
    isSaving.value = false;
  }
};

const onAddLabel = label => {
  const title = label?.title || label;
  if (!title || selectedLabelTitleSet.value.has(title)) return;

  selectedLabelTitles.value = [...selectedLabelTitles.value, title];
};

const onRemoveLabel = title => {
  if (!title || !selectedLabelTitleSet.value.has(title)) return;

  selectedLabelTitles.value = selectedLabelTitles.value.filter(
    selectedTitle => selectedTitle !== title
  );
};

const copyCardId = async () => {
  await copyTextToClipboard(cardDisplayId.value);
  useAlert(t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID_COPIED'));
};

const openConversation = () => {
  if (!hasConversation.value) return;

  emit('openConversation', card.value);
};

// --- Products tab ---

const PRICE_LIST_OPTIONS = [
  {
    value: 'default',
    label: t(
      'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_LIST_OPTIONS.DEFAULT'
    ),
  },
  {
    value: 'revenda',
    label: t(
      'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_LIST_OPTIONS.REVENDA'
    ),
  },
  {
    value: 'empresas_21_dias',
    label: t(
      'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_LIST_OPTIONS.EMPRESAS_21_DIAS'
    ),
  },
];

const searchText = ref('');
const priceList = ref('default');
const searchResults = ref([]);
const isSearching = ref(false);
const searchError = ref('');
const addDrafts = ref({});

const cardProducts = ref([]);
const isLoadingProducts = ref(false);
const productsLoadError = ref('');
const editingUnitPriceId = ref(null);
const editingUnitPriceValue = ref('');
const isUpdatingProductId = ref(null);
const isRemovingProductId = ref(null);

const totalValue = computed(() => {
  if (cardProducts.value.length) {
    return cardProducts.value.reduce(
      (sum, product) =>
        sum + Number(product.subtotal ?? product.unit_price * product.quantity),
      0
    );
  }

  return Number(card.value?.value || 0);
});

const formattedTotalValue = computed(() => formatCurrency(totalValue.value));

const loadCardProducts = async () => {
  isLoadingProducts.value = true;
  productsLoadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getCardProducts(
      props.boardId,
      props.cardId
    );
    cardProducts.value = response?.data || [];
  } catch (error) {
    productsLoadError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.LOAD_ERROR')
    );
  } finally {
    isLoadingProducts.value = false;
  }
};

const getDraft = sku => {
  if (!addDrafts.value[sku]) {
    addDrafts.value[sku] = {
      open: false,
      quantity: 1,
      priceType: 'pix',
      isSaving: false,
      error: '',
    };
  }

  return addDrafts.value[sku];
};

const toggleAddForm = product => {
  const draft = getDraft(product.sku);
  draft.open = !draft.open;
  draft.quantity = 1;
  draft.priceType = 'pix';
  draft.error = '';
};

const performSearch = async () => {
  const text = searchText.value.trim();

  if (!text) {
    searchResults.value = [];
    searchError.value = '';
    isSearching.value = false;
    return;
  }

  isSearching.value = true;
  searchError.value = '';

  try {
    const response = await ProductsAPI.search({
      text,
      price_list: priceList.value,
      limit: 20,
    });
    searchResults.value = response?.data?.products || [];
  } catch (error) {
    searchError.value = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_ERROR')
    );
  } finally {
    isSearching.value = false;
  }
};

const debouncedSearch = debounce(performSearch, 400, false);

watch([searchText, priceList], () => {
  debouncedSearch();
});

const confirmAddProduct = async product => {
  const draft = getDraft(product.sku);
  if (draft.isSaving) return;

  const maxQuantity = Math.max(Number(product.stock_quantity) || 1, 1);
  const quantity = Math.min(
    Math.max(Number(draft.quantity) || 1, 1),
    maxQuantity
  );
  const unitPrice =
    draft.priceType === 'pix'
      ? product.pricing?.pix_price
      : product.pricing?.base_price;

  draft.isSaving = true;
  draft.error = '';

  try {
    await KanbanBoardsAPI.createCardProduct(props.boardId, props.cardId, {
      sku: product.sku,
      name: product.name,
      brand: product.brand,
      image_url: product.image_url,
      quantity,
      unit_price: unitPrice,
      price_type: draft.priceType,
      price_list: priceList.value,
    });
    draft.open = false;
    await loadCardProducts();
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_SUCCESS'));
  } catch (error) {
    draft.error = getErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_ERROR')
    );
    useAlert(draft.error);
  } finally {
    draft.isSaving = false;
  }
};

const startEditUnitPrice = product => {
  if (!isAdmin.value) return;

  editingUnitPriceId.value = product.id;
  editingUnitPriceValue.value = product.unit_price;
};

const cancelEditUnitPrice = () => {
  editingUnitPriceId.value = null;
  editingUnitPriceValue.value = '';
};

const saveUnitPrice = async product => {
  if (isUpdatingProductId.value) return;

  isUpdatingProductId.value = product.id;

  try {
    await KanbanBoardsAPI.updateCardProduct(
      props.boardId,
      props.cardId,
      product.id,
      {
        unit_price: Number(editingUnitPriceValue.value),
        quantity: product.quantity,
      }
    );
    cancelEditUnitPrice();
    await loadCardProducts();
  } catch (error) {
    useAlert(
      getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.UPDATE_ERROR')
      )
    );
  } finally {
    isUpdatingProductId.value = null;
  }
};

const removeCardProduct = async product => {
  if (isRemovingProductId.value) return;

  isRemovingProductId.value = product.id;

  try {
    await KanbanBoardsAPI.deleteCardProduct(
      props.boardId,
      props.cardId,
      product.id
    );
    await loadCardProducts();
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_SUCCESS'));
  } catch (error) {
    useAlert(
      getErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_ERROR')
      )
    );
  } finally {
    isRemovingProductId.value = null;
  }
};

onMounted(async () => {
  loadCardProducts();
  await Promise.allSettled([loadCard(), loadLabels(), loadAssignees()]);
  captureSnapshot();
});

defineExpose({ saveCard, hasUnsavedChanges });
</script>

<template>
  <div
    class="mx-auto flex max-h-[92vh] w-full max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-xl bg-n-background xl:max-w-[64rem] 2xl:max-w-[72rem]"
  >
    <div
      class="flex items-center justify-between gap-4 border-b border-n-weak px-2 py-4"
    >
      <div class="flex min-w-0 items-center gap-2">
        <h2 class="mb-0 truncate text-base font-semibold text-n-slate-12">
          {{ t('KANBAN.OPPORTUNITY_DETAILS.TITLE') }}
        </h2>
        <span
          v-if="hasUnsavedChanges"
          data-testid="kanban-opportunity-unsaved-indicator"
          class="inline-flex flex-shrink-0 items-center gap-1.5 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
        >
          <span class="size-1.5 rounded-full bg-n-amber-9" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.UNSAVED_CHANGES_INDICATOR') }}
        </span>
      </div>
      <div v-if="cardDisplayId" class="flex flex-shrink-0 items-center gap-2">
        <span
          data-testid="kanban-opportunity-card-id"
          class="text-sm font-medium text-n-slate-11"
        >
          {{ t('KANBAN.OPPORTUNITY_DETAILS.CARD_ID', { id: cardDisplayId }) }}
        </span>
        <button
          type="button"
          data-testid="kanban-opportunity-copy-card-id"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID')"
          @click="copyCardId"
        >
          <i class="i-lucide-copy size-4" />
        </button>
        <button
          v-if="card"
          type="button"
          data-testid="kanban-opportunity-remove-card"
          class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-ruby-11 hover:bg-n-ruby-2"
          :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
          :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
          @click="emit('removeCard', card)"
        >
          <i class="i-lucide-trash size-4" />
        </button>
      </div>
    </div>

    <div class="flex-none border-b border-n-weak px-2 py-3">
      <TabBar
        :tabs="tabItems"
        :initial-active-tab="activeTabIndex"
        @tab-changed="onTabChanged"
      />
    </div>

    <div class="overflow-auto px-2 py-4">
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
        <section
          v-show="activeTabKey === 'general'"
          data-testid="kanban-opportunity-general-tab"
        >
          <div
            v-if="wonStageId && lostStageId"
            data-testid="kanban-opportunity-status"
            class="mb-4"
          >
            <KanbanCardStatusBadge
              :kanban-stage-id="card.kanbanStageId"
              :won-stage-id="wonStageId"
              :lost-stage-id="lostStageId"
              :reasons="reasons"
              :lost-reason-required="lostReasonRequired"
              @change="onChangeCardStatus"
            />
          </div>

          <form
            data-testid="kanban-opportunity-form"
            class="grid gap-5"
            @submit.prevent="saveCard"
          >
            <div
              data-testid="kanban-opportunity-layout"
              class="grid min-w-0 gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(16rem,18rem)]"
            >
              <section class="grid min-w-0 content-start gap-4">
                <NextInput
                  v-model="subject"
                  data-testid="kanban-opportunity-subject"
                  class="w-full"
                  :label="t('KANBAN.OPPORTUNITY_DETAILS.FIELD_TITLE')"
                  :message="subjectError"
                  :message-type="subjectError ? 'error' : 'info'"
                  autofocus
                  @input="subjectError = ''"
                />

                <section
                  class="grid min-w-0 gap-2 rounded-lg border border-n-weak p-3"
                >
                  <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.CONTACT') }}
                  </h3>
                  <p
                    data-testid="kanban-opportunity-contact"
                    class="mb-0 flex min-w-0 items-center gap-2 text-sm text-n-slate-11"
                  >
                    <Avatar
                      v-if="hasContact"
                      :name="contactName"
                      :src="card.contact.thumbnail"
                      :size="20"
                      rounded-full
                    />
                    <i
                      v-else
                      class="i-lucide-user-round size-4 flex-shrink-0"
                    />
                    <span class="min-w-0 truncate">{{ contactName }}</span>
                  </p>
                </section>

                <section class="grid gap-2 rounded-lg border border-n-weak p-3">
                  <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY') }}
                  </h3>
                  <KanbanPriorityDropdown
                    v-model="priority"
                    test-id="kanban-opportunity-priority"
                    :none-label="t('KANBAN.OPPORTUNITY_DETAILS.PRIORITY_NONE')"
                  />
                </section>

                <div class="grid min-w-0 gap-1.5">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.FIELD_DESCRIPTION') }}
                  </span>
                  <Editor
                    v-model="description"
                    data-testid="kanban-opportunity-description"
                    :show-character-count="false"
                    :placeholder="
                      t('KANBAN.OPPORTUNITY_DETAILS.DESCRIPTION_PLACEHOLDER')
                    "
                    class="max-w-full w-full [&>div]:min-h-[18rem]"
                  />
                </div>
              </section>

              <aside class="grid min-w-0 content-start gap-4">
                <section
                  class="grid min-w-0 gap-3 rounded-lg border border-n-weak p-3"
                >
                  <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.CONVERSATION') }}
                  </h3>
                  <p
                    v-if="hasConversation"
                    data-testid="kanban-opportunity-conversation"
                    class="mb-0 flex min-w-0 items-center gap-2 text-sm text-n-slate-11"
                  >
                    <ChannelIcon
                      v-if="inboxObject"
                      :inbox="inboxObject"
                      class="size-4 flex-shrink-0"
                    />
                    <i v-else class="i-lucide-inbox size-4 flex-shrink-0" />
                    <span class="min-w-0 truncate">{{ inboxName }}</span>
                  </p>
                  <p
                    v-else
                    data-testid="kanban-opportunity-no-conversation"
                    class="mb-0 flex items-center gap-2 text-sm text-n-slate-11"
                  >
                    <i class="i-lucide-message-square-off size-4" />
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LINKED_CONVERSATION') }}
                  </p>
                  <NextButton
                    v-if="hasConversation"
                    type="button"
                    outline
                    slate
                    xs
                    data-testid="kanban-opportunity-open-conversation"
                    icon="i-lucide-external-link"
                    :label="t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION')"
                    @click="openConversation"
                  />
                </section>

                <section class="grid gap-3 rounded-lg border border-n-weak p-3">
                  <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.LABELS') }}
                  </h3>
                  <p
                    v-if="labelsLoadError"
                    data-testid="kanban-opportunity-labels-load-error"
                    class="mb-0 text-sm text-n-ruby-11"
                  >
                    {{ labelsLoadError }}
                  </p>

                  <Popover
                    align="start"
                    disable-mobile-view
                    :show-content-border="false"
                  >
                    <button
                      type="button"
                      data-testid="kanban-opportunity-labels-menu"
                      class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="isLoadingLabels"
                    >
                      <i
                        class="i-lucide-tags size-4 flex-shrink-0 text-n-slate-11"
                      />
                      <span class="min-w-0 flex-1 truncate">
                        {{ selectedLabelsSummary }}
                      </span>
                      <i
                        class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
                      />
                    </button>

                    <template #content>
                      <div
                        class="block visible w-80 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
                      >
                        <LabelDropdown
                          :account-labels="accountLabels"
                          :selected-labels="selectedLabelTitles"
                          allow-creation
                          @add="onAddLabel"
                          @remove="onRemoveLabel"
                        />
                      </div>
                    </template>
                  </Popover>

                  <div
                    v-if="selectedLabels.length"
                    data-testid="kanban-opportunity-labels"
                    class="flex flex-wrap gap-2"
                  >
                    <span
                      v-for="label in selectedLabels"
                      :key="label.id || label.title"
                      data-testid="kanban-opportunity-label"
                      class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
                    >
                      <span
                        class="size-2 rounded-full"
                        :style="{ backgroundColor: label.color }"
                      />
                      <span>{{ label.title }}</span>
                    </span>
                  </div>

                  <p
                    v-else-if="!isLoadingLabels && !labelsLoadError"
                    data-testid="kanban-opportunity-no-labels"
                    class="mb-0 text-sm text-n-slate-11"
                  >
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_LABELS_SELECTED') }}
                  </p>
                </section>

                <section class="grid gap-3 rounded-lg border border-n-weak p-3">
                  <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE') }}
                  </h3>
                  <p
                    v-if="assigneesLoadError"
                    data-testid="kanban-opportunity-assignees-load-error"
                    class="mb-0 text-sm text-n-ruby-11"
                  >
                    {{ assigneesLoadError }}
                  </p>

                  <Popover
                    align="start"
                    disable-mobile-view
                    :show-content-border="false"
                  >
                    <button
                      type="button"
                      data-testid="kanban-opportunity-assignees-menu"
                      class="inline-flex min-h-10 w-full items-center gap-2 rounded-md border border-n-weak bg-n-surface-1 px-3 py-2 text-left text-sm text-n-slate-12 outline-none hover:bg-n-alpha-2 focus:border-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                      :disabled="isLoadingAssignees"
                    >
                      <i
                        class="i-lucide-users size-4 flex-shrink-0 text-n-slate-11"
                      />
                      <span class="min-w-0 flex-1 truncate">
                        {{ assigneesSummary }}
                      </span>
                      <i
                        class="i-lucide-chevron-down size-4 flex-shrink-0 text-n-slate-11"
                      />
                    </button>

                    <template #content>
                      <div
                        class="block visible w-72 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
                      >
                        <ul class="grid gap-1">
                          <li v-for="user in assignableUsers" :key="user.id">
                            <button
                              type="button"
                              data-testid="kanban-opportunity-assignee-option"
                              :data-selected="
                                selectedAssigneeIds.includes(user.id)
                              "
                              class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                              @click="onToggleAssignee(user)"
                            >
                              <input
                                type="checkbox"
                                class="pointer-events-none"
                                :checked="selectedAssigneeIds.includes(user.id)"
                                tabindex="-1"
                              />
                              <Avatar
                                :name="user.name"
                                :src="user.avatar_url"
                                :size="20"
                                rounded-full
                              />
                              <span class="min-w-0 flex-1 truncate">
                                {{ user.name }}
                              </span>
                            </button>
                          </li>
                        </ul>
                        <p
                          v-if="!assignableUsers.length"
                          class="mb-0 px-2 py-1.5 text-sm text-n-slate-11"
                        >
                          {{
                            t('KANBAN.OPPORTUNITY_DETAILS.NO_ASSIGNABLE_USERS')
                          }}
                        </p>
                      </div>
                    </template>
                  </Popover>

                  <div
                    v-if="assignedUsers.length"
                    data-testid="kanban-opportunity-assignees"
                    class="flex flex-wrap gap-2"
                  >
                    <span
                      v-for="user in assignedUsers"
                      :key="user.id"
                      data-testid="kanban-opportunity-assignee"
                      class="inline-flex items-center gap-2 rounded-full border border-n-weak bg-n-alpha-1 px-3 py-1 text-xs font-medium text-n-slate-11"
                    >
                      <Avatar
                        :name="user.name"
                        :src="user.avatar_url"
                        :size="16"
                        rounded-full
                      />
                      <span>{{ user.name }}</span>
                    </span>
                  </div>
                  <p
                    v-else-if="!isLoadingAssignees && !assigneesLoadError"
                    data-testid="kanban-opportunity-no-assignees"
                    class="mb-0 text-sm text-n-slate-11"
                  >
                    {{ t('KANBAN.OPPORTUNITY_DETAILS.UNASSIGNED') }}
                  </p>
                </section>

                <section class="grid gap-4 rounded-lg border border-n-weak p-3">
                  <div class="grid gap-1">
                    <h3 class="mb-0 text-sm font-medium text-n-slate-12">
                      {{
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.TOTAL_VALUE')
                      }}
                    </h3>
                    <p
                      data-testid="kanban-opportunity-total-value"
                      class="mb-0 text-sm text-n-slate-11"
                    >
                      {{ formattedTotalValue }}
                    </p>
                  </div>

                  <KanbanDueDatePicker
                    v-model="dueAt"
                    data-testid="kanban-opportunity-due-at"
                    :label="t('KANBAN.OPPORTUNITY_DETAILS.DUE_DATE')"
                    :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
                    :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
                  />
                </section>
              </aside>
            </div>

            <p
              v-if="saveError"
              data-testid="kanban-opportunity-save-error"
              class="mb-0 text-sm text-n-ruby-11"
            >
              {{ saveError }}
            </p>
          </form>
        </section>

        <section
          v-show="activeTabKey === 'products'"
          data-testid="kanban-opportunity-products-tab"
          class="grid min-w-0 gap-5"
        >
          <section class="grid gap-3 rounded-lg border border-n-weak p-3">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_LABEL') }}
            </h3>

            <div class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_12rem]">
              <NextInput
                v-model="searchText"
                data-testid="kanban-opportunity-product-search"
                :placeholder="
                  t(
                    'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_PLACEHOLDER'
                  )
                "
              />
              <Select
                v-model="priceList"
                data-testid="kanban-opportunity-product-price-list"
                :options="PRICE_LIST_OPTIONS"
              />
            </div>

            <p
              v-if="isSearching"
              data-testid="kanban-opportunity-products-searching"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCHING') }}
            </p>
            <p
              v-else-if="searchError"
              data-testid="kanban-opportunity-products-search-error"
              class="mb-0 text-sm text-n-ruby-11"
            >
              {{ searchError }}
            </p>
            <p
              v-else-if="!searchText.trim()"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{
                t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_EMPTY_HINT')
              }}
            </p>
            <p
              v-else-if="!searchResults.length"
              data-testid="kanban-opportunity-products-no-results"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.NO_RESULTS') }}
            </p>

            <div
              v-else
              data-testid="kanban-opportunity-product-search-results"
              class="grid gap-2"
            >
              <div
                v-for="product in searchResults"
                :key="product.sku"
                data-testid="kanban-opportunity-product-search-result"
                class="grid gap-2 rounded-md border border-n-weak bg-n-surface-1 p-3"
              >
                <div class="flex items-start gap-3">
                  <img
                    v-if="product.image_url"
                    :src="product.image_url"
                    alt=""
                    class="size-12 flex-none rounded-md object-cover"
                  />
                  <div class="grid min-w-0 flex-1 gap-0.5">
                    <span
                      class="min-w-0 truncate text-sm font-medium text-n-slate-12"
                    >
                      {{ product.name }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{ product.sku }} · {{ product.brand }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PIX_PRICE', {
                          price: formatCurrency(product.pricing?.pix_price),
                        })
                      }}
                      ·
                      {{
                        t(
                          'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.INSTALLMENT_PRICE',
                          { price: formatCurrency(product.pricing?.base_price) }
                        )
                      }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.STOCK', {
                          count: product.stock_quantity,
                        })
                      }}
                    </span>
                  </div>
                  <NextButton
                    type="button"
                    outline
                    slate
                    xs
                    data-testid="kanban-opportunity-product-add-toggle"
                    :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD')"
                    @click="toggleAddForm(product)"
                  />
                </div>

                <div
                  v-if="getDraft(product.sku).open"
                  data-testid="kanban-opportunity-product-add-form"
                  class="grid gap-3 rounded-md border border-n-weak bg-n-surface-2 p-3 sm:grid-cols-[8rem_1fr]"
                >
                  <label class="grid gap-1 text-xs font-medium text-n-slate-12">
                    {{
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_QUANTITY')
                    }}
                    <input
                      v-model.number="getDraft(product.sku).quantity"
                      type="number"
                      min="1"
                      :max="product.stock_quantity || 1"
                      data-testid="kanban-opportunity-product-add-quantity"
                      class="rounded-md border border-n-weak bg-n-surface-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                    />
                  </label>
                  <div class="grid gap-1 text-xs font-medium text-n-slate-12">
                    {{
                      t(
                        'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_TYPE'
                      )
                    }}
                    <div class="flex flex-wrap items-center gap-3 font-normal">
                      <label class="flex items-center gap-1.5 text-n-slate-12">
                        <input
                          v-model="getDraft(product.sku).priceType"
                          type="radio"
                          value="pix"
                          data-testid="kanban-opportunity-product-add-price-pix"
                        />
                        {{
                          t(
                            'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_PIX'
                          )
                        }}
                        ({{ formatCurrency(product.pricing?.pix_price) }})
                      </label>
                      <label class="flex items-center gap-1.5 text-n-slate-12">
                        <input
                          v-model="getDraft(product.sku).priceType"
                          type="radio"
                          value="base"
                          data-testid="kanban-opportunity-product-add-price-base"
                        />
                        {{
                          t(
                            'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_BASE'
                          )
                        }}
                        ({{ formatCurrency(product.pricing?.base_price) }})
                      </label>
                    </div>
                  </div>

                  <p
                    v-if="getDraft(product.sku).error"
                    class="col-span-full mb-0 text-xs text-n-ruby-11"
                  >
                    {{ getDraft(product.sku).error }}
                  </p>

                  <div class="col-span-full flex items-center gap-2">
                    <NextButton
                      type="button"
                      sm
                      data-testid="kanban-opportunity-product-add-confirm"
                      :label="
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CONFIRM')
                      "
                      :is-loading="getDraft(product.sku).isSaving"
                      @click="confirmAddProduct(product)"
                    />
                    <NextButton
                      type="button"
                      outline
                      slate
                      sm
                      :label="
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CANCEL')
                      "
                      @click="toggleAddForm(product)"
                    />
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section class="grid gap-3 rounded-lg border border-n-weak p-3">
            <h3 class="mb-0 text-sm font-medium text-n-slate-12">
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.LINKED_TITLE') }}
            </h3>

            <p
              v-if="isLoadingProducts"
              data-testid="kanban-opportunity-products-loading"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.LOADING') }}
            </p>
            <p
              v-else-if="productsLoadError"
              data-testid="kanban-opportunity-products-load-error"
              class="mb-0 text-sm text-n-ruby-11"
            >
              {{ productsLoadError }}
            </p>
            <p
              v-else-if="!cardProducts.length"
              data-testid="kanban-opportunity-products-empty"
              class="mb-0 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.EMPTY') }}
            </p>

            <div
              v-else
              data-testid="kanban-opportunity-linked-products"
              class="grid gap-2 overflow-x-auto"
            >
              <table class="w-full min-w-[36rem] text-left text-sm">
                <thead>
                  <tr class="text-xs uppercase text-n-slate-10">
                    <th class="pb-2 font-medium">
                      {{
                        t(
                          'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_PRODUCT'
                        )
                      }}
                    </th>
                    <th class="pb-2 font-medium">
                      {{
                        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SKU')
                      }}
                    </th>
                    <th class="pb-2 font-medium">
                      {{
                        t(
                          'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_QUANTITY'
                        )
                      }}
                    </th>
                    <th class="pb-2 font-medium">
                      {{
                        t(
                          'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_UNIT_PRICE'
                        )
                      }}
                    </th>
                    <th class="pb-2 font-medium">
                      {{
                        t(
                          'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SUBTOTAL'
                        )
                      }}
                    </th>
                    <th class="pb-2" />
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="product in cardProducts"
                    :key="product.id"
                    data-testid="kanban-opportunity-linked-product"
                    class="border-t border-n-weak"
                  >
                    <td class="py-2 pr-2 text-n-slate-12">
                      {{ product.name }}
                    </td>
                    <td class="py-2 pr-2 text-n-slate-11">{{ product.sku }}</td>
                    <td class="py-2 pr-2 text-n-slate-11">
                      {{ product.quantity }}
                    </td>
                    <td class="py-2 pr-2 text-n-slate-11">
                      <span
                        v-if="isAdmin && editingUnitPriceId === product.id"
                        class="flex items-center gap-1"
                      >
                        <input
                          v-model.number="editingUnitPriceValue"
                          type="number"
                          step="0.01"
                          min="0"
                          data-testid="kanban-opportunity-product-unit-price-input"
                          class="w-24 rounded-md border border-n-weak bg-n-surface-1 px-2 py-1 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                        />
                        <button
                          type="button"
                          data-testid="kanban-opportunity-product-unit-price-save"
                          class="text-n-teal-11"
                          :aria-label="
                            t(
                              'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SAVE_UNIT_PRICE'
                            )
                          "
                          @click="saveUnitPrice(product)"
                        >
                          <i class="i-lucide-check size-4" />
                        </button>
                        <button
                          type="button"
                          data-testid="kanban-opportunity-product-unit-price-cancel"
                          class="text-n-slate-11"
                          :aria-label="
                            t(
                              'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.CANCEL_EDIT'
                            )
                          "
                          @click="cancelEditUnitPrice"
                        >
                          <i class="i-lucide-x size-4" />
                        </button>
                      </span>
                      <span v-else class="flex items-center gap-1">
                        {{ formatCurrency(product.unit_price) }}
                        <button
                          v-if="isAdmin"
                          type="button"
                          data-testid="kanban-opportunity-product-unit-price-edit"
                          class="text-n-slate-10 hover:text-n-slate-12"
                          :aria-label="
                            t(
                              'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.EDIT_UNIT_PRICE'
                            )
                          "
                          @click="startEditUnitPrice(product)"
                        >
                          <i class="i-lucide-pencil size-3.5" />
                        </button>
                      </span>
                    </td>
                    <td class="py-2 pr-2 font-medium text-n-slate-12">
                      {{ formatCurrency(product.subtotal) }}
                    </td>
                    <td class="py-2 text-right">
                      <button
                        type="button"
                        data-testid="kanban-opportunity-product-remove"
                        class="text-n-ruby-11 hover:text-n-ruby-10"
                        :aria-label="
                          t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE')
                        "
                        @click="removeCardProduct(product)"
                      >
                        <i class="i-lucide-trash size-4" />
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              class="flex items-center justify-end gap-2 border-t border-n-weak pt-3 text-sm font-medium text-n-slate-12"
            >
              <span>{{
                t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.TOTAL_VALUE')
              }}</span>
              <span data-testid="kanban-opportunity-products-total">
                {{ formattedTotalValue }}
              </span>
            </div>
          </section>
        </section>

        <section
          v-show="activeTabKey === 'additional_data'"
          data-testid="kanban-opportunity-additional-data-tab"
        >
          <KanbanCardAdditionalDataTab
            ref="additionalDataTabRef"
            :board-id="boardId"
            :card-id="cardId"
            :custom-fields="customFields"
          />
        </section>
      </template>
    </div>

    <div
      v-if="hasUnsavedChanges"
      data-testid="kanban-opportunity-savebar"
      class="flex flex-none items-center justify-end gap-3 border-t border-n-weak bg-n-background px-4 py-3"
    >
      <NextButton
        type="button"
        outline
        slate
        sm
        data-testid="kanban-opportunity-cancel"
        :label="t('KANBAN.OPPORTUNITY_DETAILS.CANCEL')"
        @click="emit('close')"
      />
      <NextButton
        type="button"
        sm
        data-testid="kanban-opportunity-save"
        :label="
          isSaving
            ? t('KANBAN.OPPORTUNITY_DETAILS.SAVING')
            : t('KANBAN.OPPORTUNITY_DETAILS.SAVE_CHANGES')
        "
        :disabled="isSaving"
        :is-loading="isSaving"
        @click="saveCard"
      />
    </div>
  </div>
</template>
