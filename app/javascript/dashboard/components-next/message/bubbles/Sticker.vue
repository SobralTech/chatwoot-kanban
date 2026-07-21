<script setup>
import { computed, onMounted } from 'vue';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import { useMessageContext } from '../provider.js';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';

const { attachments } = useMessageContext();

const attachment = computed(() => attachments.value[0]);

const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry();

onMounted(() => {
  if (attachment.value?.dataUrl) {
    loadWithRetry(attachment.value.dataUrl);
  }
});
</script>

<template>
  <BaseBubble bare data-bubble-name="sticker">
    <div v-if="hasError" class="flex items-center gap-1">
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      <p class="mb-0 text-n-slate-11">
        {{ $t('COMPONENTS.MEDIA.IMAGE_UNAVAILABLE') }}
      </p>
    </div>
    <img
      v-else-if="isLoaded"
      class="object-contain skip-context-menu max-w-[8rem] max-h-[8rem]"
      :src="attachment.dataUrl"
    />
  </BaseBubble>
</template>
