<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import { reasonsOfType } from 'dashboard/helper/kanbanCardStatus';

const props = defineProps({
  modelValue: {
    type: [String, Number],
    default: '',
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  reasonType: {
    type: String,
    default: null,
  },
  required: {
    type: Boolean,
    default: false,
  },
  testid: {
    type: String,
    default: undefined,
  },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const options = computed(() => {
  const reasonOptions = reasonsOfType(props.reasons, props.reasonType).map(
    reason => ({ value: reason.id, label: reason.title })
  );

  if (props.required) return reasonOptions;

  return [
    { value: '', label: t('KANBAN.CARD.STATUS.REASON_PLACEHOLDER') },
    ...reasonOptions,
  ];
});

const selectedReasonId = computed({
  get: () => props.modelValue,
  set: value => emit('update:modelValue', value),
});
</script>

<template>
  <div class="grid gap-2">
    <label class="grid gap-1 text-xs font-medium text-n-slate-12">
      {{ t('KANBAN.CARD.STATUS.REASON_LABEL') }}
      <Select
        v-model="selectedReasonId"
        :data-testid="testid"
        :options="options"
      />
    </label>

    <p v-if="required && !modelValue" class="mb-0 text-xs text-n-ruby-11">
      {{ t('KANBAN.CARD.STATUS.REASON_REQUIRED') }}
    </p>
  </div>
</template>
