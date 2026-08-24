<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import KanbanCardStatusBadge from '../../KanbanCardStatusBadge.vue';
import KanbanDueDatePicker from '../../KanbanDueDatePicker.vue';
import KanbanPriorityDropdown from '../../KanbanPriorityDropdown.vue';
import { MENU_OPTION_CLASSES, MENU_SURFACE_CLASSES } from '../../menuClasses';

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
  isPending: {
    type: Function,
    default: () => false,
  },
});

const emit = defineEmits([
  'changeStatus',
  'openMove',
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

const isTerminalStage = stage =>
  Number(stage.id) === Number(props.wonStageId) ||
  Number(stage.id) === Number(props.lostStageId);

const currentStage = computed(() =>
  props.stages.find(
    stage => Number(stage.id) === Number(props.card.kanbanStageId)
  )
);
const stageName = computed(
  () => currentStage.value?.name || t('KANBAN.CARD.UNKNOWN_STAGE')
);
const terminal = computed(() =>
  isTerminalStage({ id: props.card.kanbanStageId })
);
const reasonTitle = computed(() => {
  if (!terminal.value || !props.card.kanbanReasonId) return '';

  return props.reasons.find(
    item => Number(item.id) === Number(props.card.kanbanReasonId)
  )?.title;
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
</script>

<template>
  <!-- Every control in this row is 28px tall so the header reads as one strip. -->
  <div
    data-testid="kanban-opportunity-quick-controls"
    class="flex min-w-0 flex-wrap items-center gap-2"
  >
    <KanbanCardStatusBadge
      v-if="wonStageId && lostStageId"
      size="md"
      :kanban-stage-id="card.kanbanStageId"
      :won-stage-id="wonStageId"
      :lost-stage-id="lostStageId"
      :reasons="reasons"
      :lost-reason-required="lostReasonRequired"
      :disabled="isPending('status') || isPending('stage')"
      @change="emit('changeStatus', $event)"
    />

    <button
      type="button"
      data-testid="kanban-opportunity-move-to"
      class="inline-flex h-7 min-w-0 items-center gap-1.5 rounded-md border border-n-weak bg-n-surface-1 px-2 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
      :title="t('KANBAN.CARD.MOVE_TO')"
      :aria-label="t('KANBAN.CARD.MOVE_TO')"
      :disabled="isPending('stage')"
      @click="emit('openMove')"
    >
      <i class="i-lucide-corner-up-right size-3 flex-shrink-0" />
      <span class="min-w-0 max-w-[10rem] truncate">{{ stageName }}</span>
      <i class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-11" />
    </button>

    <span
      v-if="reasonTitle"
      data-testid="kanban-opportunity-reason"
      class="inline-flex h-7 max-w-[14rem] items-center truncate rounded-full border border-n-weak px-2 text-xs text-n-slate-11"
      :title="
        t('KANBAN.OPPORTUNITY_DETAILS.REASON_LABEL', { reason: reasonTitle })
      "
    >
      {{
        t('KANBAN.OPPORTUNITY_DETAILS.REASON_LABEL', { reason: reasonTitle })
      }}
    </span>

    <KanbanPriorityDropdown
      v-model="priority"
      compact
      test-id="kanban-opportunity-priority"
      :disabled="isPending('priority')"
    />

    <KanbanDueDatePicker
      v-model="dueAt"
      compact
      data-testid="kanban-opportunity-due-at"
      :placeholder="t('KANBAN.OPPORTUNITY_DETAILS.CHOOSE_DATE')"
      :clear-label="t('KANBAN.OPPORTUNITY_DETAILS.CLEAR_DATE')"
      :disabled="isPending('dueAt')"
    />

    <div class="ms-auto flex min-w-0 items-center gap-2">
      <button
        v-if="hasValue"
        type="button"
        data-testid="kanban-opportunity-total-value"
        class="inline-flex h-7 max-w-[10rem] items-center truncate rounded-full border border-n-weak px-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2"
        :title="formattedTotalValue"
        @click="emit('openProducts')"
      >
        {{ formattedTotalValue }}
      </button>

      <Popover align="end" disable-mobile-view>
        <button
          type="button"
          data-testid="kanban-opportunity-assignees-menu"
          class="flex h-7 items-center gap-1 rounded-md px-1 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('KANBAN.OPPORTUNITY_DETAILS.ASSIGNEE')"
          :disabled="isPending('assignees')"
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
          <div class="w-72" :class="[MENU_SURFACE_CLASSES]">
            <ul class="grid gap-1">
              <li v-for="user in assignableUsers" :key="user.id">
                <button
                  type="button"
                  data-testid="kanban-opportunity-assignee-option"
                  :data-selected="selectedAssigneeIds.includes(Number(user.id))"
                  :disabled="isPending('assignees')"
                  :class="MENU_OPTION_CLASSES"
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
