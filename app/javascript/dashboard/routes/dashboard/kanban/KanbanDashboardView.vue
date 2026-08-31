<script setup>
import { useI18n } from 'vue-i18n';

import KanbanBoardViewShell from './board/KanbanBoardViewShell.vue';

const { t } = useI18n();
</script>

<template>
  <KanbanBoardViewShell>
    <div
      class="flex flex-1 items-center justify-center p-6 text-sm text-n-slate-11"
      data-testid="kanban-dashboard-placeholder"
    >
      {{ t('KANBAN.DASHBOARD.COMING_SOON') }}
    </div>
  </KanbanBoardViewShell>
</template>
