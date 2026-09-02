<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { useKanbanCardSla } from 'dashboard/composables/useKanbanCardSla';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import { formatCurrency } from 'dashboard/helper/kanbanCurrency';
import KanbanCardStatusBadge from '../../KanbanCardStatusBadge.vue';
import { MENU_OPTION_CLASSES, MENU_SURFACE_CLASSES } from '../../menuClasses';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  boardName: {
    type: String,
    default: '',
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
const { stageSlaStatusValue, stageSlaClasses, stageTime, stageTimeTitle } =
  useKanbanCardSla(
    computed(() => props.card),
    computed(() => currentStage.value?.slaHours)
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
  <!-- Where the deal stands: status, funnel position, what it is worth and who
  owns it. Bordered controls mark this tier; secondary attributes below stay
  borderless so the two rows do not read as one undifferentiated strip. -->
  <div
    data-testid="kanban-opportunity-quick-controls"
    class="flex min-w-0 items-start gap-3"
  >
    <div class="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-2">
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

      <!-- Funnel and stage are two halves of one fact, so they read as one
      breadcrumb instead of sitting in different rows and different styles. -->
      <div class="flex min-w-0 items-center gap-1">
        <template v-if="boardName">
          <span
            data-testid="kanban-opportunity-board-name"
            class="min-w-0 max-w-[7rem] flex-shrink truncate text-xs text-n-slate-11"
            :title="boardName"
          >
            {{ boardName }}
          </span>
          <i
            class="i-lucide-chevron-right size-3 flex-shrink-0 text-n-slate-9"
          />
        </template>

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
          <i
            class="i-lucide-chevron-down size-3 flex-shrink-0 text-n-slate-11"
          />
        </button>

        <!-- How long the card has sat in its stage belongs next to the stage. -->
        <span
          v-if="stageTime"
          data-testid="kanban-opportunity-stage-sla"
          class="ms-1 inline-flex flex-shrink-0 items-center gap-1 text-xs leading-4"
          :class="stageSlaClasses"
          :title="stageTimeTitle"
          :aria-label="
            stageSlaStatusValue === 'stale' ? t('KANBAN.CARD.SLA_STALE') : null
          "
        >
          <i class="i-lucide-clock size-3 flex-shrink-0" />
          {{ stageTime }}
        </span>
      </div>

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
    </div>

    <!-- Value and owner keep their own slot outside the wrapping group, so a
    long stage name can never push them onto a line of their own. -->
    <div class="flex flex-none items-center gap-1">
      <button
        v-if="hasValue"
        type="button"
        data-testid="kanban-opportunity-total-value"
        class="inline-flex h-7 max-w-[10rem] items-center truncate rounded-md px-1.5 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2"
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
