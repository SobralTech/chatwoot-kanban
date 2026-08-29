<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import Select from 'dashboard/components-next/select/Select.vue';
import KanbanAmountInput from './KanbanAmountInput.vue';
import { useAlert } from 'dashboard/composables';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import {
  DISCOUNT_AMOUNT,
  DISCOUNT_PERCENT,
  cardTotal,
  discountValue,
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
  itemsTotal: {
    type: Number,
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

const emit = defineEmits(['cardChanged']);
const { t } = useI18n();

const DISCOUNT_TYPE_OPTIONS = [
  {
    value: DISCOUNT_PERCENT,
    label: t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.DISCOUNT_PERCENT'),
  },
  {
    value: DISCOUNT_AMOUNT,
    label: t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.DISCOUNT_AMOUNT'),
  },
];

const isSaving = ref(false);
const error = ref('');
const type = ref(props.discountType);
const amount = ref('');

// The card is the source of truth: whenever it changes - this panel opening on
// another card, or the general tab saving - the inputs follow it rather than
// keeping whatever the previous card had.
watch(
  () => [props.discountType, props.discountAmount],
  ([nextType, nextAmount]) => {
    type.value = nextType || DISCOUNT_PERCENT;
    amount.value = nextAmount == null ? '' : Number(nextAmount);
  },
  { immediate: true }
);

const discount = computed(() => ({
  itemsTotal: props.itemsTotal,
  discountType: type.value,
  discountAmount: amount.value,
}));

const formattedItemsTotal = computed(() => formatCurrency(props.itemsTotal));
const formattedDiscount = computed(() =>
  formatCurrency(discountValue(discount.value))
);
const formattedTotal = computed(() =>
  formatCurrency(cardTotal(discount.value))
);

const save = async () => {
  if (isSaving.value) return;

  const raw = String(amount.value ?? '').trim();
  const parsed = Number(raw);
  if (raw && (!Number.isFinite(parsed) || parsed < 0)) return;

  isSaving.value = true;
  error.value = '';

  try {
    const response = await KanbanBoardsAPI.updateCardDetailsById(
      props.boardId,
      props.cardId,
      { discount_type: type.value, discount_amount: raw ? parsed : null }
    );
    emit('cardChanged', camelcaseKeys(response?.data || {}, { deep: true }));
  } catch (requestError) {
    error.value = apiErrorMessage(
      requestError,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.DISCOUNT_INVALID')
    );
    useAlert(error.value);
  } finally {
    isSaving.value = false;
  }
};

// Switching between a percentage and an amount keeps the number the user typed;
// rewriting it to the equivalent in the other unit would silently edit their input.
const changeType = nextType => {
  type.value = nextType;
  save();
};
</script>

<template>
  <div class="grid gap-2 border-t border-n-weak pt-3 text-sm">
    <div class="flex items-center justify-between gap-3 text-n-slate-11">
      <span>
        {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.SUBTOTAL_LABEL') }}
      </span>
      <span
        data-testid="kanban-opportunity-products-subtotal"
        class="tabular-nums"
      >
        {{ formattedItemsTotal }}
      </span>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-2">
      <span class="font-medium text-n-slate-12">
        {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.DISCOUNT_LABEL') }}
      </span>
      <div class="flex items-center gap-2">
        <Select
          :model-value="type"
          data-testid="kanban-opportunity-discount-type"
          :options="DISCOUNT_TYPE_OPTIONS"
          full-width
          class="w-36 [&_select]:h-10"
          @update:model-value="changeType"
        />
        <KanbanAmountInput
          v-model="amount"
          class="w-32"
          data-testid="kanban-opportunity-discount-input"
          :unit="type === DISCOUNT_PERCENT ? 'percent' : 'currency'"
          :max="type === DISCOUNT_PERCENT ? 100 : null"
          :disabled="isSaving"
          @blur="save"
          @enter="save"
        />
      </div>
    </div>

    <div
      v-if="discountValue(discount)"
      class="flex items-center justify-between gap-3 text-n-slate-11"
    >
      <span />
      <span
        data-testid="kanban-opportunity-discount-value"
        class="tabular-nums"
      >
        {{
          t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.DISCOUNT_APPLIED', {
            value: formattedDiscount,
          })
        }}
      </span>
    </div>

    <p
      v-if="error"
      data-testid="kanban-opportunity-discount-error"
      class="mb-0 text-xs text-n-ruby-11"
    >
      {{ error }}
    </p>

    <div
      class="flex items-center justify-between gap-3 border-t border-n-weak pt-2 font-semibold text-n-slate-12"
    >
      <span>
        {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.TOTAL_LABEL') }}
      </span>
      <span
        data-testid="kanban-opportunity-products-total"
        class="tabular-nums"
      >
        {{ formattedTotal }}
      </span>
    </div>
  </div>
</template>
