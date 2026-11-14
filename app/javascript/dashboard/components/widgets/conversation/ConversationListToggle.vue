<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useConversationListToggle } from 'dashboard/composables/useConversationListToggle';

const { t } = useI18n();
const listToggle = useConversationListToggle();

const label = computed(() =>
  listToggle.value.listOpen
    ? t('CONVERSATION.HEADER.HIDE_CONVERSATION_LIST')
    : t('CONVERSATION.HEADER.SHOW_CONVERSATION_LIST')
);
</script>

<template>
  <NextButton
    slate
    faded
    sm
    :icon="
      listToggle.listOpen
        ? 'i-lucide-panel-left-close'
        : 'i-lucide-panel-left-open'
    "
    :title="label"
    :aria-label="label"
    class="flex-shrink-0"
    data-testid="conversation-list-toggle"
    @click="listToggle.toggle()"
  />
</template>
