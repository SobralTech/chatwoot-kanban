<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import KanbanReasonPicker from './KanbanReasonPicker.vue';
import { MENU_OPTION_CLASSES, MENU_SURFACE_CLASSES } from './menuClasses';

const props = defineProps({
  kanbanStageId: {
    type: Number,
    default: null,
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  lostStageId: {
    type: Number,
    default: null,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  // 'md' matches the 28px control height the opportunity header row uses.
  size: {
    type: String,
    default: 'sm',
    validator: value => ['sm', 'md'].includes(value),
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['change']);

const { t } = useI18n();

const chosenType = ref(null);
const selectedReasonId = ref('');

const status = computed(() => {
  if (props.wonStageId && props.kanbanStageId === props.wonStageId) {
    return 'won';
  }
  if (props.lostStageId && props.kanbanStageId === props.lostStageId) {
    return 'lost';
  }
  return 'open';
});

const statusMetaByStatus = computed(() => ({
  open: {
    label: t('KANBAN.CARD.STATUS.OPEN'),
    icon: 'i-lucide-rotate-cw',
    classes: 'bg-n-slate-3 text-n-slate-11',
  },
  won: {
    label: t('KANBAN.CARD.STATUS.WON'),
    icon: 'i-lucide-check-circle-2',
    classes: 'bg-n-teal-3 text-n-teal-11',
  },
  lost: {
    label: t('KANBAN.CARD.STATUS.LOST'),
    icon: 'i-lucide-x-circle',
    classes: 'bg-n-ruby-3 text-n-ruby-11',
  },
}));

const statusMeta = computed(() => statusMetaByStatus.value[status.value]);

const isReasonRequired = computed(
  () => chosenType.value === 'lost' && props.lostReasonRequired
);

const canConfirm = computed(
  () => !isReasonRequired.value || !!selectedReasonId.value
);

const isReopenConfirmation = computed(() => chosenType.value === 'reopen');

const resetSelection = () => {
  chosenType.value = null;
  selectedReasonId.value = '';
};

const chooseType = type => {
  chosenType.value = type;
  selectedReasonId.value = '';
};

const backToChoices = () => {
  chosenType.value = null;
  selectedReasonId.value = '';
};

const confirm = hide => {
  if (!canConfirm.value) return;

  if (isReopenConfirmation.value) {
    emit('change', { reopen: true });
    hide?.();
    resetSelection();
    return;
  }

  const targetStageId =
    chosenType.value === 'won' ? props.wonStageId : props.lostStageId;

  emit('change', {
    targetStageId,
    reasonId: selectedReasonId.value || null,
  });

  hide?.();
  resetSelection();
};
</script>

<template>
  <Popover
    v-if="wonStageId && lostStageId"
    align="start"
    disable-mobile-view
    @hide="resetSelection"
  >
    <button
      type="button"
      data-testid="kanban-card-status-badge"
      class="inline-flex flex-shrink-0 items-center gap-1 rounded-full border border-n-weak px-2 text-xs font-medium disabled:cursor-not-allowed disabled:opacity-50"
      :class="[statusMeta.classes, size === 'md' ? 'h-7' : 'py-0.5']"
      :title="t('KANBAN.CARD.STATUS.CHANGE')"
      :disabled="disabled"
    >
      <i :class="statusMeta.icon" class="size-3" />
      {{ statusMeta.label }}
      <i class="i-lucide-chevron-down size-3" />
    </button>

    <template #content="{ hide }">
      <div class="w-56" :class="[MENU_SURFACE_CLASSES]">
        <div v-if="!chosenType && status === 'open'" class="grid gap-1.5">
          <button
            type="button"
            data-testid="kanban-card-status-option-won"
            :class="MENU_OPTION_CLASSES"
            @click="chooseType('won')"
          >
            <i class="i-lucide-check-circle-2 size-4 text-n-teal-11" />
            {{ t('KANBAN.CARD.STATUS.MARK_AS_WON') }}
          </button>
          <button
            type="button"
            data-testid="kanban-card-status-option-lost"
            :class="MENU_OPTION_CLASSES"
            @click="chooseType('lost')"
          >
            <i class="i-lucide-x-circle size-4 text-n-ruby-11" />
            {{ t('KANBAN.CARD.STATUS.MARK_AS_LOST') }}
          </button>
        </div>

        <div v-else-if="!chosenType" class="grid gap-1.5">
          <button
            type="button"
            data-testid="kanban-card-status-option-reopen"
            :class="MENU_OPTION_CLASSES"
            @click="chooseType('reopen')"
          >
            <i class="i-lucide-rotate-ccw size-4 text-n-brand" />
            {{ t('KANBAN.CARD.STATUS.REOPEN_OPPORTUNITY') }}
          </button>
        </div>

        <div v-else-if="isReopenConfirmation" class="grid gap-2">
          <p class="mb-0 text-sm text-n-slate-12">
            {{ t('KANBAN.CARD.STATUS.REOPEN_CONFIRMATION') }}
          </p>

          <div class="flex items-center justify-between gap-2 pt-1">
            <button
              type="button"
              data-testid="kanban-card-status-back"
              class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
              @click="backToChoices"
            >
              {{ t('KANBAN.CARD.STATUS.BACK') }}
            </button>
            <button
              type="button"
              data-testid="kanban-card-status-confirm"
              class="rounded-md bg-n-brand px-3 py-1.5 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="!canConfirm"
              @click="confirm(hide)"
            >
              {{ t('KANBAN.CARD.STATUS.CONFIRM') }}
            </button>
          </div>
        </div>

        <div v-else class="grid gap-2">
          <KanbanReasonPicker
            v-model="selectedReasonId"
            :reasons="reasons"
            :reason-type="chosenType"
            :required="isReasonRequired"
            testid="kanban-card-status-reason-select"
          />

          <div class="flex items-center justify-between gap-2 pt-1">
            <button
              type="button"
              data-testid="kanban-card-status-back"
              class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12"
              @click="backToChoices"
            >
              {{ t('KANBAN.CARD.STATUS.BACK') }}
            </button>
            <button
              type="button"
              data-testid="kanban-card-status-confirm"
              class="rounded-md bg-n-brand px-3 py-1.5 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
              :disabled="!canConfirm"
              @click="confirm(hide)"
            >
              {{ t('KANBAN.CARD.STATUS.CONFIRM') }}
            </button>
          </div>
        </div>
      </div>
    </template>
  </Popover>
</template>
