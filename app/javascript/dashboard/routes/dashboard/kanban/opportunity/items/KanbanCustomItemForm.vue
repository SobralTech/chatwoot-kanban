<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import KanbanBoardsAPI from 'dashboard/api/kanbanBoards';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useAlert } from 'dashboard/composables';
import { apiErrorMessage } from 'dashboard/helper/kanbanApiError';

import KanbanAmountInput from './KanbanAmountInput.vue';

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

const emit = defineEmits(['added', 'cancel']);
const { t } = useI18n();

const ITEM_TYPE_OPTIONS = [
  {
    value: 'service',
    label: t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_SERVICE'),
  },
  {
    value: 'custom',
    label: t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_CUSTOM'),
  },
];

const name = ref('');
const quantity = ref(1);
const unitPrice = ref('');
const itemType = ref('service');
const isSaving = ref(false);
const error = ref('');

const isValid = () => {
  const parsedQuantity = Number(quantity.value);
  const parsedUnitPrice = Number(unitPrice.value);

  return (
    Boolean(name.value.trim()) &&
    Number.isInteger(parsedQuantity) &&
    parsedQuantity >= 1 &&
    Number.isFinite(parsedUnitPrice) &&
    parsedUnitPrice >= 0
  );
};

const submit = async () => {
  if (isSaving.value) return;

  if (!isValid()) {
    error.value = t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_ERROR');
    return;
  }

  isSaving.value = true;
  error.value = '';

  try {
    await KanbanBoardsAPI.createCardProduct(props.boardId, props.cardId, {
      name: name.value.trim(),
      quantity: Number(quantity.value),
      unit_price: Number(unitPrice.value),
      item_type: itemType.value,
    });
    name.value = '';
    quantity.value = 1;
    unitPrice.value = '';
    emit('added');
    useAlert(t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_SUCCESS'));
  } catch (requestError) {
    error.value = apiErrorMessage(
      requestError,
      t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_ERROR')
    );
    useAlert(error.value);
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form
    data-testid="kanban-opportunity-custom-item-form"
    class="grid gap-3 rounded-md border border-n-weak bg-n-surface-2 p-3 sm:grid-cols-[minmax(0,1fr)_8rem_10rem]"
    @submit.prevent="submit"
  >
    <label class="grid gap-1 text-xs font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_NAME') }}
      <input
        v-model="name"
        type="text"
        data-testid="kanban-opportunity-custom-item-name"
        class="reset-base !mb-0 block h-10 w-full rounded-lg border-none bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand font-normal"
      />
    </label>
    <label class="grid gap-1 text-xs font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_QUANTITY') }}
      <input
        v-model.number="quantity"
        type="number"
        min="1"
        data-testid="kanban-opportunity-custom-item-quantity"
        class="reset-base !mb-0 block h-10 w-full rounded-lg border-none bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand text-right font-normal tabular-nums"
      />
    </label>
    <label class="grid gap-1 text-xs font-medium text-n-slate-12">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.COLUMN_UNIT_PRICE') }}
      <KanbanAmountInput
        v-model="unitPrice"
        data-testid="kanban-opportunity-custom-item-unit-price"
        unit="currency"
      />
    </label>
    <div class="grid gap-1 text-xs font-medium text-n-slate-12 sm:col-span-2">
      {{ t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ITEM_TYPE_LABEL') }}
      <Select
        v-model="itemType"
        data-testid="kanban-opportunity-custom-item-type"
        :options="ITEM_TYPE_OPTIONS"
        full-width
        class="[&_select]:h-10"
      />
    </div>
    <p v-if="error" class="mb-0 text-xs text-n-ruby-11 sm:col-span-3">
      {{ error }}
    </p>
    <div class="flex items-center gap-2 sm:col-span-3">
      <NextButton
        type="submit"
        sm
        data-testid="kanban-opportunity-custom-item-submit"
        :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CONFIRM')"
        :is-loading="isSaving"
      />
      <NextButton
        type="button"
        outline
        slate
        sm
        :label="t('KANBAN.OPPORTUNITY_DETAILS.PRODUCTS_TAB.ADD_CANCEL')"
        @click="emit('cancel')"
      />
    </div>
  </form>
</template>
