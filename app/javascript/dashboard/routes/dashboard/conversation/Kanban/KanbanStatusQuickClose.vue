<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import { useKanbanCardStatusActions } from 'dashboard/composables/useKanbanCardStatusActions';
import KanbanStatusReasonForm from '../../kanban/KanbanStatusReasonForm.vue';
import { MENU_SURFACE_CLASSES } from '../../kanban/menuClasses';

const props = defineProps({
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
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const { canSkipReason, statusPayloadFor } = useKanbanCardStatusActions({
  wonStageId: toRef(props, 'wonStageId'),
  lostStageId: toRef(props, 'lostStageId'),
  reasons: toRef(props, 'reasons'),
  lostReasonRequired: toRef(props, 'lostReasonRequired'),
});

const actions = computed(() => [
  {
    type: 'won',
    testid: 'kanban-conversation-card-won',
    labelKey: 'KANBAN.CARD.STATUS.MARK_AS_WON',
    icon: 'i-lucide-check-circle-2',
    hoverClass: 'hover:text-n-teal-11',
    required: false,
  },
  {
    type: 'lost',
    testid: 'kanban-conversation-card-lost',
    labelKey: 'KANBAN.CARD.STATUS.MARK_AS_LOST',
    icon: 'i-lucide-x-circle',
    hoverClass: 'hover:text-n-ruby-11',
    required: props.lostReasonRequired,
  },
]);

const popoverRefs = {};

const closeOpportunity = (type, reasonId, hide) => {
  hide?.();
  emit('close', statusPayloadFor(type, reasonId));
};

const onTriggerClick = action => {
  if (canSkipReason(action.type)) {
    closeOpportunity(action.type, null, () => popoverRefs[action.type]?.hide());
    return;
  }

  popoverRefs[action.type]?.show();
};
</script>

<template>
  <Popover
    v-for="action in actions"
    :key="action.type"
    :ref="el => (popoverRefs[action.type] = el)"
    align="end"
    disable-mobile-view
  >
    <button
      type="button"
      :data-testid="action.testid"
      class="flex size-8 items-center justify-center rounded-md text-n-slate-10 hover:bg-n-alpha-2 focus:outline-none focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-50"
      :class="action.hoverClass"
      :aria-label="t(action.labelKey)"
      :title="t(action.labelKey)"
      :disabled="disabled"
      @click.stop="onTriggerClick(action)"
    >
      <i :class="action.icon" class="size-5" />
    </button>
    <template #content="{ hide }">
      <div class="w-56" :class="[MENU_SURFACE_CLASSES]">
        <KanbanStatusReasonForm
          :reason-type="action.type"
          :reasons="reasons"
          :required="action.required"
          :show-back="false"
          @confirm="reasonId => closeOpportunity(action.type, reasonId, hide)"
        />
      </div>
    </template>
  </Popover>
</template>
