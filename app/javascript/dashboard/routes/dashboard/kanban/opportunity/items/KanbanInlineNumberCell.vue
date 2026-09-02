<script setup>
import { computed, nextTick, ref } from 'vue';

import { formatCurrency } from 'dashboard/helper/kanbanCurrency';

// A line item's numbers are its own controls: the value reads as plain text
// until it is hovered, becomes a focused input on click, and commits on Enter or
// blur. The linked items list already saves on every change, so a separate
// pencil, confirm and cancel button per cell only ate the column width.
const props = defineProps({
  modelValue: { type: [Number, String], default: 0 },
  unit: {
    type: String,
    default: 'currency',
    validator: value => ['currency', 'integer'].includes(value),
  },
  label: { type: String, required: true },
  readonly: { type: Boolean, default: false },
  readonlyHint: { type: String, default: '' },
  isSaving: { type: Boolean, default: false },
  dataTestid: { type: String, default: undefined },
});

const emit = defineEmits(['save']);

const isCurrency = computed(() => props.unit === 'currency');
const isEditing = ref(false);
const draft = ref('');
const inputRef = ref(null);

const displayValue = computed(() =>
  isCurrency.value ? formatCurrency(props.modelValue) : String(props.modelValue)
);

const startEdit = async () => {
  if (props.readonly || props.isSaving) return;

  draft.value = String(props.modelValue ?? '');
  isEditing.value = true;
  await nextTick();
  inputRef.value?.select();
};

const closeEdit = () => {
  isEditing.value = false;
  draft.value = '';
};

// An empty or out-of-range entry reverts instead of saving: a blank price would
// silently zero the line and a blank quantity fails the server's validation.
const commit = () => {
  if (!isEditing.value) return;

  const parsed = Number(String(draft.value).trim());
  const isValid = isCurrency.value
    ? Number.isFinite(parsed) && parsed >= 0
    : Number.isInteger(parsed) && parsed >= 1;

  closeEdit();

  if (!isValid || parsed === Number(props.modelValue)) return;

  emit('save', parsed);
};
</script>

<template>
  <span
    v-if="readonly"
    :title="readonlyHint || undefined"
    class="block truncate py-1 text-right tabular-nums text-n-slate-11"
  >
    {{ displayValue }}
  </span>

  <input
    v-else-if="isEditing"
    ref="inputRef"
    v-model="draft"
    type="number"
    :min="isCurrency ? 0 : 1"
    :step="isCurrency ? '0.01' : '1'"
    :aria-label="label"
    :data-testid="dataTestid"
    class="reset-base !mb-0 block h-8 w-full rounded-md border-none bg-n-surface-1 px-2 py-1 text-right text-sm tabular-nums text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-brand [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
    @keydown.enter.prevent="commit"
    @keydown.esc.prevent="closeEdit"
    @blur="commit"
  />

  <button
    v-else
    type="button"
    :aria-label="`${label}: ${displayValue}`"
    :data-testid="dataTestid ? `${dataTestid}-trigger` : undefined"
    :disabled="isSaving"
    class="block h-8 w-full truncate rounded-md px-2 py-1 text-right text-sm tabular-nums text-n-slate-11 outline outline-1 -outline-offset-1 outline-transparent transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12 hover:outline-n-weak focus-visible:outline-n-brand disabled:opacity-50"
    @click="startEdit"
  >
    {{ displayValue }}
  </button>
</template>
