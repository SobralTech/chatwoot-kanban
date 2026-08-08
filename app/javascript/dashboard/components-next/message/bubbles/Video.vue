<script setup>
import { ref, computed, watch, nextTick, useTemplateRef } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMediaRetry } from 'dashboard/composables/useMediaRetry';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';

const showGallery = ref(false);
const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const { hasError, cacheBustedUrl, scheduleRetry, reset } = useMediaRetry();

const videoPlayer = useTemplateRef('videoPlayer');

const attachment = computed(() => {
  return attachments.value[0];
});

watch(() => attachment.value?.id, reset);

const videoUrl = computed(() => cacheBustedUrl(attachment.value.dataUrl));

const handleError = () => {
  scheduleRetry(async () => {
    await nextTick();
    videoPlayer.value?.load();
  });
};

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="showGallery = true"
  >
    <div v-if="hasError" class="flex items-center gap-1 text-center rounded-lg">
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      <p class="mb-0 text-n-slate-11">
        {{ $t('COMPONENTS.MEDIA.VIDEO_UNAVAILABLE') }}
      </p>
    </div>
    <div v-else class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        ref="videoPlayer"
        controls
        class="rounded-lg skip-context-menu"
        :src="videoUrl"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @click.stop
        @error="handleError"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @close="() => (showGallery = false)"
  />
</template>
