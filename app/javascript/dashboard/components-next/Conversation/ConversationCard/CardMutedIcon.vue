<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  muted: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
</script>

<template>
  <Icon
    v-if="muted"
    v-tooltip.top="{
      content: t('CONVERSATION.CARD_CONTEXT_MENU.NOTIFICATIONS_MUTED'),
      delay: { show: 500, hide: 0 },
    }"
    icon="i-lucide-volume-x"
    class="size-3.5 text-n-slate-9"
  />
</template>
