import { computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';

import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { useSlaClock } from 'dashboard/composables/useSlaClock';
import {
  SLA_STALE,
  SLA_WARNING,
  stageSlaStatus,
} from 'dashboard/helper/kanbanStageSla';

const STATUS_CLASSES = {
  [SLA_WARNING]: 'rounded-full bg-n-amber-3 px-1.5 py-0.5 text-n-amber-11',
  [SLA_STALE]: 'rounded-full bg-n-ruby-3 px-1.5 py-0.5 text-n-ruby-11',
};

const toUnixTimestamp = value => {
  if (!value) return null;
  if (typeof value === 'number') return value;

  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? null : Math.floor(timestamp / 1000);
};

// How long a card has sat in its stage, and how that reads against the stage's
// time limit. Board requests arrive camelCased while realtime card payloads keep
// the API's snake_case, so the two spellings converge here rather than at each
// read site.
export function useKanbanCardSla(card, slaHours) {
  const { t } = useI18n();
  const now = useSlaClock();

  const enteredAt = computed(() => {
    const value = toValue(card);
    return value.stageEnteredAt ?? value.stage_entered_at;
  });

  const enteredAtTimestamp = computed(() => toUnixTimestamp(enteredAt.value));

  const status = computed(() =>
    stageSlaStatus({
      stageEnteredAt: enteredAt.value,
      slaHours: toValue(slaHours),
      now: now.value,
    })
  );

  const stageTime = computed(() =>
    enteredAtTimestamp.value
      ? shortTimestamp(dynamicTime(enteredAtTimestamp.value), true)
      : ''
  );

  const stageTimeTitle = computed(() => {
    if (!stageTime.value) return undefined;

    const age = dynamicTime(enteredAtTimestamp.value);
    const hours = toValue(slaHours);
    if (!hours) return age;

    return t('KANBAN.CARD.SLA_TOOLTIP', { age, hours });
  });

  return {
    stageEnteredAt: enteredAtTimestamp,
    stageSlaStatusValue: status,
    stageSlaClasses: computed(() => STATUS_CLASSES[status.value] || ''),
    stageTime,
    stageTimeTitle,
  };
}
