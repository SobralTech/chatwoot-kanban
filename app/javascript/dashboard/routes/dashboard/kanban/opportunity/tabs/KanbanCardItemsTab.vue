<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import ProductsAPI from 'dashboard/api/products';
import NextButton from 'dashboard/components-next/button/Button.vue';
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

import KanbanAmountInput from '../items/KanbanAmountInput.vue';
import KanbanCardDiscountFooter from '../items/KanbanCardDiscountFooter.vue';
import KanbanCustomItemForm from '../items/KanbanCustomItemForm.vue';

const { t } = useI18n();
const { isAdmin } = useAdmin();

const normalizePayload = payload =>
  camelcaseKeys(payload || {}, { deep: true });
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
const editingQuantityId = ref(null);
const editingQuantityValue = ref('');
const isUpdatingProductId = ref(null);
const isRemovingProductId = ref(null);
const isCustomItemFormOpen = ref(false);

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
      price_list: priceList.value,
      limit: 20,
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

const startEditUnitPrice = product => {
  if (!canEditUnitPrice(product)) return;

  editingUnitPriceId.value = product.id;
  editingUnitPriceValue.value = product.unitPrice;
};

const cancelEditUnitPrice = () => {
  editingUnitPriceId.value = null;
  editingUnitPriceValue.value = '';
};

const startEditQuantity = product => {
  editingQuantityId.value = product.id;
  editingQuantityValue.value = product.quantity;
};

const cancelEditQuantity = () => {
  editingQuantityId.value = null;
  editingQuantityValue.value = '';
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
    emitCardChange();
  } catch (error) {
    useAlert(
      apiErrorMessage(
        error,
        t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.UPDATE_ERROR')
      )
    );
  } finally {
    isUpdatingProductId.value = null;
  }
};

const saveQuantity = async product => {
  if (isUpdatingProductId.value) return;

  isUpdatingProductId.value = product.id;

  try {
    await KanbanBoardsAPI.updateCardProduct(
      props.boardId,
      props.cardId,
      product.id,
      { quantity: Number(editingQuantityValue.value) }
    );
    cancelEditQuantity();
    await loadCardProducts();
    emitCardChange();
  } catch (error) {
    useAlert(
      apiErrorMessage(
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
        class="grid gap-2 overflow-x-auto"
      >
        <table class="w-full min-w-[30rem] text-left text-sm">
          <thead>
            <tr class="text-xs text-n-slate-10">
              <th class="pb-2 font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_PRODUCT')
                }}
              </th>
              <th class="pb-2 font-medium">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SKU') }}
              </th>
              <th class="pb-2 pr-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_QUANTITY')
                }}
              </th>
              <th class="pb-2 pr-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_UNIT_PRICE')
                }}
              </th>
              <th class="pb-2 pr-2 text-right font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SUBTOTAL')
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
                <div class="grid gap-0.5">
                  <span>{{ product.name }}</span>
                  <span
                    v-if="product.itemType !== CATALOG_ITEM_TYPE"
                    class="text-xs text-n-slate-10"
                  >
                    {{
                      product.itemType === 'service'
                        ? t(
                            'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_SERVICE'
                          )
                        : t(
                            'KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_CUSTOM'
                          )
                    }}
                  </span>
                </div>
              </td>
              <td class="py-2 pr-2 text-n-slate-11">
                {{
                  product.sku ||
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.NO_SKU')
                }}
              </td>
              <td class="py-2 pr-2 text-right tabular-nums text-n-slate-11">
                <span
                  v-if="editingQuantityId === product.id"
                  class="flex items-center justify-end gap-1"
                >
                  <input
                    v-model.number="editingQuantityValue"
                    type="number"
                    min="1"
                    data-testid="kanban-opportunity-product-quantity-input"
                    class="reset-base !mb-0 block h-10 w-full rounded-lg border-none bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand w-20 text-right tabular-nums"
                  />
                  <button
                    type="button"
                    data-testid="kanban-opportunity-product-quantity-save"
                    class="text-n-teal-11"
                    :aria-label="
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SAVE_QUANTITY')
                    "
                    @click="saveQuantity(product)"
                  >
                    <i class="i-lucide-check size-4" />
                  </button>
                  <button
                    type="button"
                    data-testid="kanban-opportunity-product-quantity-cancel"
                    class="text-n-slate-11"
                    :aria-label="
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.CANCEL_EDIT')
                    "
                    @click="cancelEditQuantity"
                  >
                    <i class="i-lucide-x size-4" />
                  </button>
                </span>
                <span v-else class="flex items-center justify-end gap-1">
                  {{ product.quantity }}
                  <button
                    type="button"
                    data-testid="kanban-opportunity-product-quantity-edit"
                    class="text-n-slate-10 hover:text-n-slate-12"
                    :aria-label="
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.EDIT_QUANTITY')
                    "
                    @click="startEditQuantity(product)"
                  >
                    <i class="i-lucide-pencil size-3.5" />
                  </button>
                </span>
              </td>
              <td class="py-2 pr-2 text-right tabular-nums text-n-slate-11">
                <span
                  v-if="
                    canEditUnitPrice(product) &&
                    editingUnitPriceId === product.id
                  "
                  class="flex items-center justify-end gap-1"
                >
                  <KanbanAmountInput
                    v-model="editingUnitPriceValue"
                    class="w-28"
                    data-testid="kanban-opportunity-product-unit-price-input"
                    unit="currency"
                    @enter="saveUnitPrice(product)"
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
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.CANCEL_EDIT')
                    "
                    @click="cancelEditUnitPrice"
                  >
                    <i class="i-lucide-x size-4" />
                  </button>
                </span>
                <span v-else class="flex items-center justify-end gap-1">
                  {{ formatCurrency(product.unitPrice) }}
                  <button
                    v-if="canEditUnitPrice(product)"
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
              <td
                class="py-2 pr-2 text-right font-medium tabular-nums text-n-slate-12"
              >
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

      <KanbanCardDiscountFooter
        :board-id="boardId"
        :card-id="cardId"
        :items-total="itemsTotal"
        :discount-type="discountType"
        :discount-amount="discountAmount"
        @card-changed="emit('cardChanged', $event)"
      />
    </section>
  </section>
</template>
