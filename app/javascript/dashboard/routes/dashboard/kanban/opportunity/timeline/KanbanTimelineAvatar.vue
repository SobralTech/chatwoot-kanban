<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  user: { type: Object, default: null },
});

const { t } = useI18n();
</script>

<template>
  <div class="flex size-8 flex-none items-center justify-center">
    <Avatar
      v-if="user"
      :name="user.name"
      :src="user.avatarUrl"
      :size="28"
      rounded-full
    />
    <span
      v-else
      class="flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
      :title="t('KANBAN.OPPORTUNITY_DETAILS.TIMELINE.SYSTEM_AUTHOR')"
    >
      <i class="i-lucide-settings size-4" />
    </span>
  </div>
</template>
