<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import { SLA_STALE } from 'dashboard/helper/kanbanStageSla';
import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';
import KanbanCardStatusBadge from '../../KanbanCardStatusBadge.vue';
import KanbanDueDatePicker from '../../KanbanDueDatePicker.vue';
import KanbanPriorityDropdown from '../../KanbanPriorityDropdown.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  wonStageId: {
    type: Number,
    default: null,
  },
  lostStageId: {
    type: Number,
    default: null,
  },
  lostReasonRequired: {
    type: Boolean,
    default: false,
  },
  reasons: {
    type: Array,
    default: () => [],
  },
  moveToStage: {
    type: Function,
    required: true,
  },
  totalValue: {
    type: Number,
    default: 0,
  },
  assignedUsers: {
    type: Array,
    default: () => [],
  },
  assignableUsers: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits([
  'changeStatus',
  'stageMoved',
  'openProducts',
  'toggleAssignee',
]);

const priority = defineModel('priority', {
  type: String,
  default: '',
});
const dueAt = defineModel('dueAt', {
  type: String,
  default: '',
});

const { t } = useI18n();
const isMovingStage = ref(false);
const stageSelection = ref(props.card.kanbanStageId || '');

const isTerminalStage = stage =>
  Number(stage.id) === Number(props.wonStageId) ||
  Number(stage.id) === Number(props.lostStageId);

const stageOptions = computed(() => {
  const options = props.stages
    .filter(stage => !isTerminalStage(stage))
    .map(stage => ({ value: stage.id, label: stage.name }));
  const currentStage = props.stages.find(
    stage => Number(stage.id) === Number(props.card.kanbanStageId)
  );

  if (currentStage && isTerminalStage(currentStage)) {
    options.push({
      value: currentStage.id,
      label: currentStage.name,
      disabled: true,
    });
  }

  return options;
});

const currentStage = computed(() =>
  props.stages.find(
    stage => Number(stage.id) === Number(props.card.kanbanStageId)
  )
);
const terminal = computed(() =>
  isTerminalStage({ id: props.card.kanbanStageId })
);
const reasonId = computed(
  () => props.card.kanbanReasonId ?? props.card.kanban_reason_id
);
const reasonTitle = computed(() => {
  if (!terminal.value || !reasonId.value) return '';

  return props.reasons.find(item => Number(item.id) === Number(reasonId.value))
    ?.title;
});
const hasValue = computed(() => Number(props.totalValue) > 0);
const formattedTotalValue = computed(() => formatCurrency(props.totalValue));
const visibleAssignees = computed(() => props.assignedUsers.slice(0, 3));
const extraAssigneeCount = computed(() =>
  Math.max(props.assignedUsers.length - visibleAssignees.value.length, 0)
);
const selectedAssigneeIds = computed(() =>
  props.assignedUsers.map(user => Number(user.id))
);
const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => currentStage.value?.slaHours)
  );

watch(
  () => props.card.kanbanStageId,
  stageId => {
    stageSelection.value = stageId || '';
  }
);

const onStageChanged = async stageId => {
  const targetStageId = Number(stageId);
  const currentStageId = Number(props.card.kanbanStageId);
  if (!targetStageId || targetStageId === currentStageId) return;

  isMovingStage.value = true;
  const moved = await props.moveToStage(props.card, targetStageId);
  isMovingStage.value = false;

  if (moved === false) {
    stageSelection.value = currentStageId || '';
    return;
  }

  emit('stageMoved', targetStageId);
};
</script>

<template>
  <div
    data-testid="kanban-opportunity-quick-controls"
    class="flex min-w-0 flex-wrap items-center gap-2"
  >
    <KanbanCardStatusBadge
      v-if="wonStageId && lostStageId"
      :kanban-stage-id="card.kanbanStageId"
      :won-stage-id="wonStageId"
      :lost-stage-id="lostStageId"
      :reasons="reasons"
      :lost-reason-required="lostReasonRequired"
      :disabled="isMovingStage"
      @change="emit('changeStatus', $event)"
    />

    <span
      v-if="reasonTitle"
      data-testid="kanban-opportunity-reason"
      class="max-w-[14rem] truncate rounded-full border border-n-weak px-2 py-1 text-xs text-n-slate-11"
      :title="
        t('KANBAN.OPPORTUNITY_DETAILS.REASON_LABEL', { reason: reasonTitle })
      "
    >
      {{
        t('KANBAN.OPPORTUNITY_DETAILS.REASON_LABEL', { reason: reasonTitle })
      }}
    </span>

    <Select
      v-if="stageOptions.length"
      v-model="stageSelection"
      data-testid="kanban-opportunity-stage-select"
      :options="stageOptions"
      :disabled="isMovingStage"
      :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.MOVE_TO_STAGE')"
      @update:model-value="onStageChanged"
    />
    <span
      v-if="stageTime"
      data-testid="kanban-opportunity-stage-sla"
      class="inline-flex min-w-0 items-center gap-1 truncate text-xs"
      :class="stageSlaClasses"
      :title="stageTimeTitle"
      :aria-label="
        stageSlaStatusValue === SLA_STALE
          ? t('KANBAN.CARD.SLA_STALE')
          : undefined
      "
    >
      <i class="i-lucide-clock size-3 flex-shrink-0" />
      <span class="truncate">{{ stageTime }}</span>
    </span>

    <KanbanPriorityDropdown
      v-model="priority"
      compact
      test-id="kanban-opportunity-priority"
    />

    <KanbanDueDatePicker
      v-model="dueAt"
      compact
      data-testid="kanban-opportunity-due-at"
      :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
      :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
    />

    <div class="ms-auto flex min-w-0 items-center gap-2">
      <button
        v-if="hasValue"
        type="button"
        data-testid="kanban-opportunity-total-value"
        class="max-w-[10rem] truncate rounded-full border border-n-weak px-2 py-1 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2"
        :title="formattedTotalValue"
        @click="emit('openProducts')"
      >
        {{ formattedTotalValue }}
      </button>

      <Popover align="end" disable-mobile-view :show-content-border="false">
        <button
          type="button"
          data-testid="kanban-opportunity-assignees-menu"
          class="flex min-h-7 items-center gap-1 rounded-md px-1 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE')"
        >
          <template v-if="visibleAssignees.length">
            <span
              v-for="user in visibleAssignees"
              :key="user.id"
              data-testid="kanban-opportunity-assignee"
              class="flex flex-shrink-0"
              :title="user.name"
            >
              <Avatar
                :name="user.name"
                :src="user.avatarUrl"
                :size="24"
                rounded-full
              />
            </span>
            <span
              v-if="extraAssigneeCount"
              class="flex size-6 items-center justify-center rounded-full bg-n-slate-3 text-[10px] font-medium text-n-slate-11"
            >
              {{
                t('KANBAN.OPPORTUNITY_DETAILS.MORE_ITEMS', {
                  count: extraAssigneeCount,
                })
              }}
            </span>
          </template>
          <i
            v-else
            class="i-lucide-user-plus size-4"
            :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE')"
          />
        </button>

        <template #content>
          <div
            class="block visible w-72 rounded-lg border border-n-strong bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px] dark:border-n-strong"
          >
            <ul class="grid gap-1">
              <li v-for="user in assignableUsers" :key="user.id">
                <button
                  type="button"
                  data-testid="kanban-opportunity-assignee-option"
                  :data-selected="selectedAssigneeIds.includes(Number(user.id))"
                  class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="emit('toggleAssignee', user)"
                >
                  <input
                    type="checkbox"
                    class="pointer-events-none"
                    :checked="selectedAssigneeIds.includes(Number(user.id))"
                    tabindex="-1"
                  />
                  <Avatar
                    :name="user.name"
                    :src="user.avatarUrl"
                    :size="20"
                    rounded-full
                  />
                  <span class="min-w-0 flex-1 truncate">{{ user.name }}</span>
                </button>
              </li>
            </ul>
            <p
              v-if="!assignableUsers.length"
              class="mb-0 px-2 py-1.5 text-sm text-n-slate-11"
            >
              {{ t('KANBAN.OPPORTUNITY_DETAILS.NO_ASSIGNABLE_USERS') }}
            </p>
          </div>
        </template>
      </Popover>
    </div>
  </div>
</template>
