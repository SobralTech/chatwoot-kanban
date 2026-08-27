<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useEmbeddedConversation } from 'dashboard/composables/useEmbeddedConversation';

const { t } = useI18n();
const embedded = useEmbeddedConversation();

const label = computed(() =>
  embedded.value.listOpen
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
      embedded.listOpen
        ? 'i-lucide-panel-left-close'
        : 'i-lucide-panel-left-open'
    "
    :title="label"
    :aria-label="label"
    class="flex-shrink-0"
    data-testid="embedded-conversation-list-toggle"
    @click="embedded.toggleList()"
  />
</template>
