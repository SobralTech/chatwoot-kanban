<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import ProductsAPI from 'dashboard/api/products';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import {
  DISCOUNT_PERCENT,
  cardTotal,
  itemsTotalOf,
} from 'dashboard/helper/kanbanDiscount';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
  discountType: {
    type: String,
    default: DISCOUNT_PERCENT,
  },
  discountAmount: {
    type: [Number, String],
    default: null,
  },
});
const emit = defineEmits(['totalChanged', 'cardChanged']);
const CATALOG_ITEM_TYPE = 'catalog';
import { debounce } from '@chatwoot/utils';

import KanbanCardDiscountFooter from '../items/KanbanCardDiscountFooter.vue';
import KanbanCustomItemForm from '../items/KanbanCustomItemForm.vue';
import KanbanInlineNumberCell from '../items/KanbanInlineNumberCell.vue';

const { t } = useI18n();
const { isAdmin } = useAdmin();

const normalizePayload = payload =>
  camelcaseKeys(payload || {}, { deep: true });
// --- Products tab ---

// The products API rejects any limit above 10.
const SEARCH_RESULT_LIMIT = 10;
const SKU_PATTERN = /^\d+$/;

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
const isUpdatingProductId = ref(null);
const isRemovingProductId = ref(null);
const isCustomItemFormOpen = ref(false);
const removeDialogRef = ref(null);
const productPendingRemoval = ref(null);

const itemsTotal = computed(() => itemsTotalOf(cardProducts.value));

const totalValue = computed(() =>
  cardTotal({
    itemsTotal: itemsTotal.value,
    discountType: props.discountType,
    discountAmount: props.discountAmount,
  })
);

// Loading products only refreshes what the header displays; a mutation also has
// to tell the panel the stored card changed.
const emitCardTotal = () => emit('totalChanged', totalValue.value);
const emitCardChange = () => emit('cardChanged', { value: totalValue.value });

const loadCardProducts = async () => {
  isLoadingProducts.value = true;
  productsLoadError.value = '';

  try {
    const response = await KanbanBoardsAPI.getCardProducts(
      props.boardId,
      props.cardId
    );
    cardProducts.value = normalizePayload(response?.data || []);
    emitCardTotal();
  } catch (error) {
    productsLoadError.value = apiErrorMessage(
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
      // The API matches SKUs only through its own `sku` field, never through
      // the free-text one, so an all-digits term is sent as both.
      ...(SKU_PATTERN.test(text) ? { sku: text } : {}),
      price_list: priceList.value,
      limit: SEARCH_RESULT_LIMIT,
    });
    searchResults.value = normalizePayload(response?.data).products || [];
  } catch (error) {
    searchError.value = apiErrorMessage(
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

  const maxQuantity = Math.max(Number(product.stockQuantity) || 1, 1);
  const quantity = Math.min(
    Math.max(Number(draft.quantity) || 1, 1),
    maxQuantity
  );
  const unitPrice =
    draft.priceType === 'pix'
      ? product.pricing?.pixPrice
      : product.pricing?.basePrice;

  draft.isSaving = true;
  draft.error = '';

  try {
    await KanbanBoardsAPI.createCardProduct(props.boardId, props.cardId, {
      sku: product.sku,
      name: product.name,
      brand: product.brand,
      image_url: product.imageUrl,
      quantity,
      unit_price: unitPrice,
      price_type: draft.priceType,
      price_list: priceList.value,
    });
    draft.open = false;
    await loadCardProducts();
    emitCardChange();
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_SUCCESS'));
  } catch (error) {
    draft.error = apiErrorMessage(
      error,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_ERROR')
    );
    useAlert(draft.error);
  } finally {
    draft.isSaving = false;
  }
};

// Mirrors the rule the products controller enforces: a catalog price comes from
// the price list and only an administrator may override it, while manually added
// lines are priced on the card itself.
const canEditUnitPrice = product =>
  product.itemType !== CATALOG_ITEM_TYPE || isAdmin.value;

const PRICE_TYPE_KEYS = {
  pix: 'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_TAG_PIX',
  base: 'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_TAG_BASE',
};

// The SKU, the item type and the price the line was quoted at are metadata, not
// columns to scan, so they ride under the name and give the money columns room.
const itemMeta = product => {
  const parts = [
    product.sku
      ? t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SKU_VALUE', {
          sku: product.sku,
        })
      : t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.NO_SKU'),
  ];

  if (product.itemType !== CATALOG_ITEM_TYPE) {
    parts.push(
      t(
        product.itemType === 'service'
          ? 'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_SERVICE'
          : 'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_CUSTOM'
      )
    );
  } else if (PRICE_TYPE_KEYS[product.priceType]) {
    parts.push(t(PRICE_TYPE_KEYS[product.priceType]));
  }

  const priceListOption = PRICE_LIST_OPTIONS.find(
    option => option.value === product.priceList
  );
  if (priceListOption && priceListOption.value !== 'default') {
    parts.push(priceListOption.label);
  }

  return parts.join(' · ');
};

const updateCardProduct = async (product, payload, errorKey) => {
  if (isUpdatingProductId.value) return;

  isUpdatingProductId.value = product.id;

  try {
    await KanbanBoardsAPI.updateCardProduct(
      props.boardId,
      props.cardId,
      product.id,
      payload
    );
    await loadCardProducts();
    emitCardChange();
  } catch (error) {
    useAlert(apiErrorMessage(error, t(errorKey)));
  } finally {
    isUpdatingProductId.value = null;
  }
};

const saveUnitPrice = (product, unitPrice) =>
  updateCardProduct(
    product,
    { unit_price: unitPrice },
    'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.UPDATE_ERROR'
  );

const saveQuantity = (product, quantity) =>
  updateCardProduct(
    product,
    { quantity },
    'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.UPDATE_QUANTITY_ERROR'
  );

const requestRemoveCardProduct = product => {
  productPendingRemoval.value = product;
  removeDialogRef.value?.open();
};

const confirmRemoveCardProduct = async () => {
  const product = productPendingRemoval.value;
  if (!product || isRemovingProductId.value) return;

  isRemovingProductId.value = product.id;

  try {
    await KanbanBoardsAPI.deleteCardProduct(
      props.boardId,
      props.cardId,
      product.id
    );
    removeDialogRef.value?.close();
    productPendingRemoval.value = null;
    await loadCardProducts();
    emitCardChange();
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_SUCCESS'));
  } catch (error) {
    useAlert(
      apiErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_ERROR')
      )
    );
  } finally {
    isRemovingProductId.value = null;
  }
};

const onCustomItemAdded = async () => {
  isCustomItemFormOpen.value = false;
  await loadCardProducts();
  emitCardChange();
};

onMounted(loadCardProducts);

defineExpose({ reload: loadCardProducts });
</script>

<template>
  <section
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
            t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_PLACEHOLDER')
          "
        />
        <Select
          v-model="priceList"
          data-testid="kanban-opportunity-product-price-list"
          :options="PRICE_LIST_OPTIONS"
          full-width
          class="[&_select]:h-10"
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
      <p v-else-if="!searchText.trim()" class="mb-0 text-sm text-n-slate-11">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SEARCH_EMPTY_HINT') }}
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
              v-if="product.imageUrl"
              :src="product.imageUrl"
              alt=""
              class="size-12 flex-none rounded-md object-cover"
            />
            <div class="grid min-w-0 flex-1 gap-0.5">
              <span
                :title="product.name"
                class="min-w-0 line-clamp-2 text-sm font-medium text-n-slate-12"
              >
                {{ product.name }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ product.sku }} · {{ product.brand }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PIX_PRICE', {
                    price: formatCurrency(product.pricing?.pixPrice),
                  })
                }}
                ·
                {{
                  t(
                    'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.INSTALLMENT_PRICE',
                    { price: formatCurrency(product.pricing?.basePrice) }
                  )
                }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.STOCK', {
                    count: product.stockQuantity,
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
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_QUANTITY') }}
              <input
                v-model.number="getDraft(product.sku).quantity"
                type="number"
                min="1"
                :max="product.stockQuantity || 1"
                data-testid="kanban-opportunity-product-add-quantity"
                class="reset-base !mb-0 block h-10 w-full rounded-lg border-none bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand tabular-nums"
              />
            </label>
            <div class="grid gap-1 text-xs font-medium text-n-slate-12">
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_TYPE') }}
              <div class="flex flex-wrap items-center gap-3 font-normal">
                <label class="flex items-center gap-1.5 text-n-slate-12">
                  <input
                    v-model="getDraft(product.sku).priceType"
                    type="radio"
                    value="pix"
                    data-testid="kanban-opportunity-product-add-price-pix"
                  />
                  {{
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_PIX')
                  }}
                  ({{ formatCurrency(product.pricing?.pixPrice) }})
                </label>
                <label class="flex items-center gap-1.5 text-n-slate-12">
                  <input
                    v-model="getDraft(product.sku).priceType"
                    type="radio"
                    value="base"
                    data-testid="kanban-opportunity-product-add-price-base"
                  />
                  {{
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_BASE')
                  }}
                  ({{ formatCurrency(product.pricing?.basePrice) }})
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
                :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CANCEL')"
                @click="toggleAddForm(product)"
              />
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="grid gap-3 rounded-lg border border-n-weak p-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.LINKED_TITLE') }}
          </h3>
          <span
            data-testid="kanban-opportunity-products-autosaved"
            class="inline-flex items-center gap-1 text-xs text-n-slate-10"
          >
            <i class="i-lucide-check size-3" />
            {{ t('KANBAN.OPPORTUNITY_DETAILS.AUTOSAVED_TAB') }}
          </span>
        </div>
        <NextButton
          type="button"
          outline
          slate
          xs
          data-testid="kanban-opportunity-add-custom-item"
          :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CUSTOM_ITEM')"
          @click="isCustomItemFormOpen = !isCustomItemFormOpen"
        />
      </div>

      <KanbanCustomItemForm
        v-if="isCustomItemFormOpen"
        :board-id="boardId"
        :card-id="cardId"
        @added="onCustomItemAdded"
        @cancel="isCustomItemFormOpen = false"
      />

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
        class="min-w-0"
      >
        <table class="w-full table-fixed text-left text-sm">
          <colgroup>
            <col />
            <col class="w-14" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-8" />
          </colgroup>
          <thead>
            <tr class="text-xs text-n-slate-10">
              <th scope="col" class="pb-2 font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_PRODUCT')
                }}
              </th>
              <th scope="col" class="pb-2 pe-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_QUANTITY')
                }}
              </th>
              <th scope="col" class="pb-2 pe-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_UNIT_PRICE')
                }}
              </th>
              <th scope="col" class="pb-2 pe-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SUBTOTAL')
                }}
              </th>
              <th scope="col" class="pb-2">
                <span class="sr-only">
                  {{
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_ACTIONS')
                  }}
                </span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="product in cardProducts"
              :key="product.id"
              data-testid="kanban-opportunity-linked-product"
              class="border-t border-n-weak align-top transition-opacity"
              :class="{
                'opacity-50':
                  isUpdatingProductId === product.id ||
                  isRemovingProductId === product.id,
              }"
            >
              <td class="py-3 pe-3">
                <p
                  :title="product.name"
                  class="mb-0 line-clamp-2 text-sm text-n-slate-12"
                >
                  {{ product.name }}
                </p>
                <p class="mb-0 truncate text-xs text-n-slate-10">
                  {{ itemMeta(product) }}
                </p>
              </td>
              <td class="py-1.5">
                <KanbanInlineNumberCell
                  :model-value="product.quantity"
                  unit="integer"
                  :label="
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.EDIT_QUANTITY')
                  "
                  :is-saving="isUpdatingProductId === product.id"
                  data-testid="kanban-opportunity-product-quantity-input"
                  @save="saveQuantity(product, $event)"
                />
              </td>
              <td class="py-1.5">
                <KanbanInlineNumberCell
                  :model-value="product.unitPrice"
                  unit="currency"
                  :label="
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.EDIT_UNIT_PRICE')
                  "
                  :readonly="!canEditUnitPrice(product)"
                  :readonly-hint="
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.PRICE_LOCKED')
                  "
                  :is-saving="isUpdatingProductId === product.id"
                  data-testid="kanban-opportunity-product-unit-price-input"
                  @save="saveUnitPrice(product, $event)"
                />
              </td>
              <td
                class="py-3 pe-2 text-right font-medium tabular-nums text-n-slate-12"
              >
                {{ formatCurrency(product.subtotal) }}
              </td>
              <td class="py-2.5 text-right">
                <button
                  type="button"
                  data-testid="kanban-opportunity-product-remove"
                  class="rounded-md p-1 text-n-slate-10 transition-colors hover:bg-n-alpha-1 hover:text-n-ruby-11 focus-visible:text-n-ruby-11"
                  :aria-label="
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE')
                  "
                  @click="requestRemoveCardProduct(product)"
                >
                  <i class="i-lucide-trash-2 size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <KanbanCardDiscountFooter
        :board-id="boardId"
        :card-id="cardId"
        :items-total="itemsTotal"
        :discount-type="discountType"
        :discount-amount="discountAmount"
        @card-changed="emit('cardChanged', $event)"
      />
    </section>

    <Dialog
      ref="removeDialogRef"
      type="alert"
      data-testid="kanban-opportunity-product-remove-dialog"
      :title="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_CONFIRM_TITLE')"
      :description="
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE_CONFIRM_BODY', {
          name: productPendingRemoval?.name,
        })
      "
      :cancel-button-label="
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CANCEL')
      "
      :confirm-button-label="
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.REMOVE')
      "
      :is-loading="Boolean(isRemovingProductId)"
      @confirm="confirmRemoveCardProduct"
    />
  </section>
</template>
