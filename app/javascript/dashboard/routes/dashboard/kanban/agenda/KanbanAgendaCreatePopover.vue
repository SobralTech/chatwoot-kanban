<script setup>
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({
  date: {
    type: Date,
    required: true,
  },
});

const emit = defineEmits(['createNew', 'scheduleExisting']);

const { t } = useI18n();

const createNewCard = hide => {
  hide();
  emit('createNew');
};

const scheduleExistingCard = hide => {
  hide();
  emit('scheduleExisting');
};
</script>

<template>
  <Popover align="end" disable-mobile-view>
    <button
      type="button"
      class="flex size-6 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-brand"
      :aria-label="t('KANBAN.AGENDA.ADD_FOR_DATE', { date: date.getDate() })"
      data-testid="kanban-agenda-add"
    >
      <i class="i-lucide-plus size-4" />
    </button>

    <template #content="{ hide }">
      <div
        class="w-56 bg-n-surface-2 p-1"
        data-testid="kanban-agenda-create-popover"
      >
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
          data-testid="kanban-agenda-create-new"
          @click="createNewCard(hide)"
        >
          <i class="i-lucide-square-plus size-4 text-n-slate-11" />
          {{ t('KANBAN.AGENDA.ADD_POPOVER.CREATE_NEW') }}
        </button>
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
          data-testid="kanban-agenda-schedule-existing"
          @click="scheduleExistingCard(hide)"
        >
          <i class="i-lucide-calendar-clock size-4 text-n-slate-11" />
          {{ t('KANBAN.AGENDA.ADD_POPOVER.SCHEDULE_EXISTING') }}
        </button>
      </div>
    </template>
  </Popover>
</template>
