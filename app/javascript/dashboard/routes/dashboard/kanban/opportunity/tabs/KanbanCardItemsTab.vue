<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import ProductsAPI from 'dashboard/api/products';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import { debounce } from '@chatwoot/utils';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  cardId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['totalChanged']);
const { t } = useI18n();
const { isAdmin } = useAdmin();

const getErrorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.message || fallback;
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

const totalValue = computed(() =>
  cardProducts.value.reduce(
    (sum, product) =>
      sum + Number(product.subtotal ?? product.unit_price * product.quantity),
    0
  )
);

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
    emit('totalChanged', totalValue.value);
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

onMounted(loadCardProducts);

defineExpose({ reload: loadCardProducts });
</script>

<template>
  <section
    data-testid="kanban-opportunity-products-tab"
    class="grid min-w-0 gap-5"
  >
    <span
      data-testid="kanban-opportunity-products-autosaved"
      class="inline-flex w-fit items-center rounded-full bg-n-teal-2 px-2 py-0.5 text-xs font-medium text-n-teal-11"
    >
      {{ t('KANBAN.OPPORTUNITY_DETAILS.AUTOSAVED_TAB') }}
    </span>
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
              {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_QUANTITY') }}
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
                    t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_PRICE_BASE')
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
                :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CANCEL')"
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
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_PRODUCT')
                }}
              </th>
              <th class="pb-2 font-medium">
                {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_SKU') }}
              </th>
              <th class="pb-2 font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_QUANTITY')
                }}
              </th>
              <th class="pb-2 font-medium">
                {{
                  t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_UNIT_PRICE')
                }}
              </th>
              <th class="pb-2 font-medium">
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
                      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.CANCEL_EDIT')
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
</template>
