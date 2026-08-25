<script setup>
import { computed, ref, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import { useKanbanCardStatusActions } from 'dashboard/composables/useKanbanCardStatusActions';
import KanbanStatusMenuItems from './KanbanStatusMenuItems.vue';
import KanbanStatusReasonForm from './KanbanStatusReasonForm.vue';
import { MENU_SURFACE_CLASSES } from './menuClasses';

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

const { hasTerminals, status, isOpen, canSkipReason, statusPayloadFor } =
  useKanbanCardStatusActions({
    stageId: toRef(props, 'kanbanStageId'),
    wonStageId: toRef(props, 'wonStageId'),
    lostStageId: toRef(props, 'lostStageId'),
    reasons: toRef(props, 'reasons'),
    lostReasonRequired: toRef(props, 'lostReasonRequired'),
  });

const chosenType = ref(null);

const statusMeta = computed(
  () =>
    ({
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
    })[status.value]
);

const isReasonRequired = computed(
  () => chosenType.value === 'lost' && props.lostReasonRequired
);

const resetSelection = () => {
  chosenType.value = null;
};

const changeStatusTo = (type, reasonId, hide) => {
  emit('change', statusPayloadFor(type, reasonId));
  hide?.();
  resetSelection();
};

const onSelectStatus = (type, hide) => {
  if (canSkipReason(type)) {
    changeStatusTo(type, null, hide);
    return;
  }

  chosenType.value = type;
};
</script>

<template>
  <Popover
    v-if="hasTerminals"
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
        <div v-if="!chosenType" class="grid gap-1.5">
          <KanbanStatusMenuItems
            testid-prefix="kanban-card-status-option"
            :is-open="isOpen"
            @select="type => onSelectStatus(type, hide)"
          />
        </div>

        <KanbanStatusReasonForm
          v-else
          :reason-type="chosenType"
          :reasons="reasons"
          :required="isReasonRequired"
          @back="resetSelection"
          @confirm="reasonId => changeStatusTo(chosenType, reasonId, hide)"
        />
      </div>
    </template>
  </Popover>
</template>
