<script setup>
import { computed, useTemplateRef, watch } from 'vue';
import { useMediaRetry } from 'dashboard/composables/useMediaRetry';

const props = defineProps({
  url: { type: String, default: '' },
});

const emit = defineEmits(['error']);

const audioPlayer = useTemplateRef('audioPlayer');
const { hasError, cacheBustedUrl, createRetryHandler } = useMediaRetry();

const audioUrl = computed(() => cacheBustedUrl(props.url));
const onAudioError = createRetryHandler(audioPlayer);

// Only surfaced once the retries are exhausted, so a message that arrives
// before its file is readable still recovers on its own.
watch(hasError, () => emit('error'));
</script>

<template>
  <!-- src lives on the element, not on a <source> child: a child only runs the
  resource selection once, so an element mounted for a message that arrived over
  the websocket can settle on NETWORK_NO_SOURCE and never recover, and its
  failure never reaches @error since source errors do not bubble. -->
  <audio
    ref="audioPlayer"
    :src="audioUrl"
    controls
    class="h-10 dark:invert"
    @error="onAudioError"
  />
</template>
