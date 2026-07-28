<script setup>
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useEmbeddedConversation } from 'dashboard/composables/useEmbeddedConversation';

const embedded = useEmbeddedConversation();
</script>

<template>
  <NextButton
    slate
    faded
    sm
    icon="i-lucide-arrow-left"
    :label="$t('GENERAL_SETTINGS.BACK')"
    class="flex-shrink-0"
    data-testid="embedded-conversation-back"
    @click="embedded.goBack()"
  />
</template>
