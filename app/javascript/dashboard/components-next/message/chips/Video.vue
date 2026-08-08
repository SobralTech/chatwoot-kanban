<script setup>
import { ref, computed, watch, useTemplateRef } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMediaRetry } from 'dashboard/composables/useMediaRetry';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const showGallery = ref(false);

const { filteredCurrentChatAttachments } = useMessageContext();

const videoPlayer = useTemplateRef('videoPlayer');

const { hasError, cacheBustedUrl, createRetryHandler, reset } = useMediaRetry();

watch(() => attachment.id, reset);

const videoUrl = computed(() => cacheBustedUrl(attachment.dataUrl));

const handleError = createRetryHandler(videoPlayer);
</script>

<template>
  <div
    class="size-[72px] overflow-hidden contain-content rounded-xl cursor-pointer relative group"
    @click="showGallery = true"
  >
    <div
      v-if="hasError"
      class="flex flex-col items-center justify-center gap-1 text-xs text-center rounded-lg size-full bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </div>
    <template v-else>
      <video
        ref="videoPlayer"
        :src="videoUrl"
        class="w-full h-full object-cover"
        muted
        playsInline
        @error="handleError"
      />
      <div
        class="absolute w-full h-full inset-0 p-1 flex items-center justify-center"
      >
        <div
          class="size-7 bg-n-slate-1/60 backdrop-blur-sm rounded-full overflow-hidden shadow-[0_5px_15px_rgba(0,0,0,0.4)]"
        >
          <Icon
            icon="i-teenyicons-play-small-solid"
            class="size-7 text-n-slate-12/80 backdrop-blur"
          />
        </div>
      </div>
    </template>
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @close="() => (showGallery = false)"
  />
</template>
