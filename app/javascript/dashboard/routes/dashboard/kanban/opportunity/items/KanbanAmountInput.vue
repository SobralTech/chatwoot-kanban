<script setup>
import { computed } from 'vue';

// Money and percentage inputs across the card panel share one field shape, so
// the discount row and the unit price cells line up on the same baseline.
const props = defineProps({
  modelValue: { type: [Number, String], default: '' },
  unit: {
    type: String,
    default: 'currency',
    validator: value => ['currency', 'percent'].includes(value),
  },
  min: { type: [Number, String], default: 0 },
  max: { type: [Number, String], default: null },
  step: { type: [Number, String], default: '0.01' },
  disabled: { type: Boolean, default: false },
  dataTestid: { type: String, default: undefined },
});

const emit = defineEmits(['update:modelValue', 'blur', 'enter']);

const isCurrency = computed(() => props.unit === 'currency');

const onInput = event => {
  const { value } = event.target;
  emit('update:modelValue', value === '' ? '' : Number(value));
};
</script>

<template>
  <div class="relative">
    <span
      class="pointer-events-none absolute inset-y-0 flex items-center text-sm text-n-slate-10"
      :class="isCurrency ? 'start-3' : 'end-3'"
    >
      {{ isCurrency ? 'R$' : '%' }}
    </span>
    <input
      :value="modelValue"
      :data-testid="dataTestid"
      type="number"
      :min="min"
      :max="max"
      :step="step"
      :disabled="disabled"
      class="reset-base !mb-0 block h-10 w-full rounded-lg border-none bg-n-surface-1 py-2 text-right text-sm tabular-nums text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:outline-n-slate-6 focus:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
      :class="isCurrency ? 'pe-3 ps-9' : 'pe-8 ps-3'"
      @input="onInput"
      @blur="emit('blur', $event)"
      @keyup.enter.prevent="emit('enter', $event)"
    />
  </div>
</template>
