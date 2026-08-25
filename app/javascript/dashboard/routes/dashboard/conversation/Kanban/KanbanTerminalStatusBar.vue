<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import KanbanStatusReasonForm from '../../kanban/KanbanStatusReasonForm.vue';
import { MENU_SURFACE_CLASSES } from '../../kanban/menuClasses';

const props = defineProps({
  stageId: {
    type: Number,
    default: null,
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  reasonId: {
    type: Number,
    default: null,
  },
  // For a terminal card, stage_entered_at is the closing date itself.
  enteredAt: {
    type: [String, Number],
    default: null,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['reopen']);

const { t } = useI18n();

const popoverRef = ref(null);

const META_BY_TYPE = {
  won: {
    icon: 'i-lucide-check-circle-2',
    classes: 'bg-n-teal-3 text-n-teal-11',
    labelKey: 'KANBAN.CARD.STATUS.WON',
  },
  lost: {
    icon: 'i-lucide-x-circle',
    classes: 'bg-n-ruby-3 text-n-ruby-11',
    labelKey: 'KANBAN.CARD.STATUS.LOST',
  },
};

const meta = computed(
  () => META_BY_TYPE[props.stageId === props.wonStageId ? 'won' : 'lost']
);
const reason = computed(() =>
  props.reasons.find(item => Number(item.id) === Number(props.reasonId))
);
const label = computed(() => {
  const status = t(meta.value.labelKey);
  return reason.value
    ? t('KANBAN.CARD.STATUS.WITH_REASON', {
        status,
        reason: reason.value.title,
      })
    : status;
});
const closedOnLabel = computed(() => {
  if (!props.enteredAt) return '';

  const date = new Date(props.enteredAt);
  return Number.isNaN(date.getTime()) ? '' : format(date, 'dd/MM');
});

const onReopenConfirm = hide => {
  hide();
  emit('reopen');
};
</script>

<template>
  <div class="min-w-0 w-full [&>span]:w-full">
    <Popover ref="popoverRef" align="start" disable-mobile-view>
      <button
        type="button"
        data-testid="kanban-conversation-card-terminal-status"
        class="flex h-10 w-full min-w-0 items-center gap-1.5 rounded-md px-3 text-xs font-medium disabled:cursor-not-allowed disabled:opacity-50"
        :class="meta.classes"
        :disabled="disabled"
        @click.stop="popoverRef?.show()"
      >
        <i :class="meta.icon" class="size-3 flex-shrink-0" />
        <span class="min-w-0 truncate" :title="label">{{ label }}</span>
        <span
          v-if="closedOnLabel"
          class="ms-auto flex-shrink-0 pl-1"
          :title="
            t('CONVERSATION_SIDEBAR.KANBAN.CLOSED_ON', {
              date: closedOnLabel,
            })
          "
        >
          {{ closedOnLabel }}
        </span>
      </button>
      <template #content="{ hide }">
        <div class="w-56" :class="[MENU_SURFACE_CLASSES]">
          <KanbanStatusReasonForm
            reason-type="reopen"
            @confirm="onReopenConfirm(hide)"
          />
        </div>
      </template>
    </Popover>
  </div>
</template>
