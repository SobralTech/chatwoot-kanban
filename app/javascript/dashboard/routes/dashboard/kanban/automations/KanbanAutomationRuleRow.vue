<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';

const props = defineProps({
  rule: {
    type: Object,
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  automationsEnabled: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['edit', 'duplicate', 'log', 'toggle', 'delete']);

const { t } = useI18n();

const eventLabels = computed(() => ({
  card_created: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_CREATED'),
  stage_changed: t('KANBAN.AUTOMATIONS.FORM.EVENTS.STAGE_CHANGED'),
  card_won: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_WON'),
  card_lost: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_LOST'),
  card_reopened: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_REOPENED'),
  card_stalled: t('KANBAN.AUTOMATIONS.FORM.EVENTS.CARD_STALLED'),
  due_soon: t('KANBAN.AUTOMATIONS.FORM.EVENTS.DUE_SOON'),
  overdue: t('KANBAN.AUTOMATIONS.FORM.EVENTS.OVERDUE'),
  no_reply: t('KANBAN.AUTOMATIONS.FORM.EVENTS.NO_REPLY'),
}));

const eventLabel = computed(() => {
  const key = props.rule.eventName || props.rule.event_name;
  return eventLabels.value[key] || key;
});

const conditionLabels = computed(() => ({
  stage_id: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.STAGE'),
  previous_stage_id: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PREVIOUS_STAGE'),
  priority: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.PRIORITY'),
  labels: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.LABELS'),
  assignee_id: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ASSIGNEE'),
  inbox_id: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.INBOX'),
  total_value: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.TOTAL_VALUE'),
  hours_in_stage: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.HOURS_IN_STAGE'),
  reason_id: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.REASON'),
  origin: t('KANBAN.AUTOMATIONS.FORM.CONDITIONS.ORIGIN'),
  contact_has_open_card: t(
    'KANBAN.AUTOMATIONS.FORM.CONDITIONS.CONTACT_HAS_OPEN_CARD'
  ),
}));

const operatorLabels = computed(() => ({
  equal_to: t('FILTER.OPERATOR_LABELS.equal_to'),
  not_equal_to: t('FILTER.OPERATOR_LABELS.not_equal_to'),
  is_present: t('FILTER.OPERATOR_LABELS.is_present'),
  is_not_present: t('FILTER.OPERATOR_LABELS.is_not_present'),
  greater_than: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.greater_than'),
  less_than: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.less_than'),
  is_one_of: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.is_one_of'),
  includes: t('KANBAN.AUTOMATIONS.FORM.OPERATORS.includes'),
}));

const operatorLabel = operator => operatorLabels.value[operator] || operator;

const stageName = stageId =>
  props.stages.find(stage => Number(stage.id) === Number(stageId))?.name ||
  stageId;

// The list is camelised on the way in, so a condition arrives as
// { attributeKey, filterOperator, values }.
const conditionValue = condition => {
  if (['is_present', 'is_not_present'].includes(condition.filterOperator)) {
    return '';
  }

  const stageCondition = ['stage_id', 'previous_stage_id'].includes(
    condition.attributeKey
  );
  return (condition.values || [])
    .map(value => (stageCondition ? stageName(value) : value))
    .join(', ');
};

const conditionSummary = computed(() => {
  const [condition] = props.rule.conditions || [];
  if (!condition) return t('KANBAN.AUTOMATIONS.FORM.NO_CONDITIONS');

  const label =
    conditionLabels.value[condition.attributeKey] || condition.attributeKey;
  return `${label} ${operatorLabel(condition.filterOperator)} ${conditionValue(condition)}`.trim();
});

const actionCount = computed(() => (props.rule.actions || []).length);

const summary = computed(() =>
  t('KANBAN.AUTOMATIONS.ROW.SUMMARY', {
    event: eventLabel.value,
    condition: conditionSummary.value,
    count: actionCount.value,
  })
);

const stateKey = computed(() => {
  if (!props.automationsEnabled) return 'PAUSED';
  if (props.rule.dryRun ?? props.rule.dry_run) return 'SIMULATION';
  return props.rule.active ? 'ACTIVE' : 'INACTIVE';
});

const stateLabels = computed(() => ({
  ACTIVE: t('KANBAN.AUTOMATIONS.STATE.ACTIVE'),
  SIMULATION: t('KANBAN.AUTOMATIONS.STATE.SIMULATION'),
  INACTIVE: t('KANBAN.AUTOMATIONS.STATE.INACTIVE'),
  PAUSED: t('KANBAN.AUTOMATIONS.STATE.PAUSED'),
}));

const stateLabel = computed(() => stateLabels.value[stateKey.value]);

const stateClasses = computed(() => {
  if (stateKey.value === 'SIMULATION') {
    return 'bg-n-amber-2 text-n-amber-11';
  }
  if (stateKey.value === 'ACTIVE') return 'bg-n-teal-2 text-n-teal-11';
  if (stateKey.value === 'PAUSED') return 'bg-n-ruby-2 text-n-ruby-11';
  return 'bg-n-alpha-2 text-n-slate-11';
});

const menuItems = computed(() => [
  {
    label: t('KANBAN.AUTOMATIONS.MENU.EDIT'),
    icon: 'i-lucide-pencil',
    click: () => emit('edit', props.rule),
  },
  {
    label: t('KANBAN.AUTOMATIONS.MENU.DUPLICATE'),
    icon: 'i-lucide-copy',
    click: () => emit('duplicate', props.rule),
  },
  {
    label: t('KANBAN.AUTOMATIONS.MENU.VIEW_LOG'),
    icon: 'i-lucide-list',
    click: () => emit('log', props.rule),
  },
  {
    label: props.rule.active
      ? t('KANBAN.AUTOMATIONS.MENU.DEACTIVATE')
      : t('KANBAN.AUTOMATIONS.MENU.ACTIVATE'),
    icon: props.rule.active ? 'i-lucide-pause' : 'i-lucide-play',
    click: () => emit('toggle', props.rule),
  },
  {
    label: t('KANBAN.AUTOMATIONS.MENU.DELETE'),
    icon: 'i-lucide-trash',
    click: () => emit('delete', props.rule),
  },
]);
</script>

<template>
  <article
    class="grid gap-2 rounded-lg border border-n-weak bg-n-surface-1 px-3 py-3"
    :data-testid="`kanban-automation-rule-${rule.id}`"
  >
    <div class="flex min-w-0 items-center gap-3">
      <span
        class="automation-drag-handle flex size-7 flex-none cursor-grab items-center justify-center rounded-md text-n-slate-10 hover:bg-n-alpha-2"
        :title="t('KANBAN.AUTOMATIONS.ROW.DRAG_TO_REORDER')"
      >
        <i class="i-lucide-grip-vertical size-4" />
      </span>
      <div class="min-w-0 flex-1">
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <h3 class="mb-0 min-w-0 truncate text-sm font-medium text-n-slate-12">
            {{ rule.name }}
          </h3>
          <span
            class="flex-none rounded-full px-2 py-0.5 text-xs font-medium"
            :class="stateClasses"
          >
            {{ stateLabel }}
          </span>
          <span class="flex-none text-xs text-n-slate-10">
            {{
              t('KANBAN.AUTOMATIONS.RUNS_7D', {
                count: rule.executionsCount || rule.executions_count || 0,
              })
            }}
          </span>
        </div>
        <p class="mb-0 mt-1 truncate text-xs text-n-slate-11">
          {{ summary }}
        </p>
      </div>

      <DropdownContainer>
        <template #trigger="{ toggle }">
          <Button
            icon="i-lucide-ellipsis"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('KANBAN.AUTOMATIONS.ROW.MORE_ACTIONS')"
            :title="t('KANBAN.AUTOMATIONS.ROW.MORE_ACTIONS')"
            @click="toggle"
          />
        </template>
        <DropdownBody class="right-0 top-0 z-50 min-w-48" strong>
          <DropdownSection>
            <DropdownItem
              v-for="item in menuItems"
              :key="item.label"
              :label="item.label"
              :icon="item.icon"
              :click="item.click"
              :class="{ 'text-n-ruby-11': item.icon === 'i-lucide-trash' }"
            />
          </DropdownSection>
        </DropdownBody>
      </DropdownContainer>
    </div>
  </article>
</template>
