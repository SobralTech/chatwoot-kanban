<script setup>
import { computed, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import { REPLY_EDITOR_MODES } from './constants';

const props = defineProps({
  mode: {
    type: String,
    default: REPLY_EDITOR_MODES.REPLY,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isReplyRestricted: {
    type: Boolean,
    default: false,
  },
  showAssistant: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['setMode']);

const wootEditorReplyMode = useTemplateRef('wootEditorReplyMode');
const wootEditorPrivateMode = useTemplateRef('wootEditorPrivateMode');
const wootEditorAssistantMode = useTemplateRef('wootEditorAssistantMode');

const replyModeSize = useElementSize(wootEditorReplyMode);
const privateModeSize = useElementSize(wootEditorPrivateMode);
const assistantModeSize = useElementSize(wootEditorAssistantMode);

const activeMode = computed(() => {
  if (props.isReplyRestricted) {
    return props.mode === REPLY_EDITOR_MODES.ASSISTANT
      ? REPLY_EDITOR_MODES.ASSISTANT
      : REPLY_EDITOR_MODES.NOTE;
  }

  return props.mode;
});

const width = computed(() => {
  const sizeMap = {
    [REPLY_EDITOR_MODES.REPLY]: replyModeSize.width.value,
    [REPLY_EDITOR_MODES.NOTE]: privateModeSize.width.value,
    [REPLY_EDITOR_MODES.ASSISTANT]: assistantModeSize.width.value,
  };

  return `${(sizeMap[activeMode.value] || replyModeSize.width.value) + 16}px`;
});

const translateValue = computed(() => {
  if (activeMode.value === REPLY_EDITOR_MODES.NOTE) {
    return `${replyModeSize.width.value + 16}px`;
  }

  if (activeMode.value === REPLY_EDITOR_MODES.ASSISTANT) {
    return `${replyModeSize.width.value + privateModeSize.width.value + 32}px`;
  }

  return '0px';
});

const setMode = mode => {
  emit('setMode', mode);
};
</script>

<template>
  <div
    class="flex items-center w-auto h-8 p-1 transition-all border rounded-full bg-n-alpha-2 group relative duration-300 ease-in-out z-0 active:scale-[0.995] active:duration-75"
    :class="{
      'cursor-not-allowed': disabled,
    }"
  >
    <button
      ref="wootEditorReplyMode"
      class="flex items-center gap-1 px-2 z-20 h-6"
      :disabled="disabled || isReplyRestricted"
      type="button"
      @click="setMode(REPLY_EDITOR_MODES.REPLY)"
    >
      {{ $t('CONVERSATION.REPLYBOX.REPLY') }}
    </button>
    <button
      ref="wootEditorPrivateMode"
      class="flex items-center gap-1 px-2 z-20 h-6"
      :disabled="disabled"
      type="button"
      @click="setMode(REPLY_EDITOR_MODES.NOTE)"
    >
      {{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE') }}
    </button>
    <button
      v-if="showAssistant"
      ref="wootEditorAssistantMode"
      class="flex items-center gap-1 px-2 z-20 h-6"
      :disabled="disabled"
      type="button"
      @click="setMode(REPLY_EDITOR_MODES.ASSISTANT)"
    >
      <span class="i-woot-openai" />
      {{ $t('CONVERSATION.REPLYBOX.ASSISTANT') }}
    </button>
    <div
      class="absolute pointer-events-none shadow-sm rounded-full h-6 w-[var(--chip-width)] ease-in-out translate-x-[var(--translate-x)] rtl:translate-x-[var(--rtl-translate-x)] bg-n-solid-1"
      :class="{
        'transition-all duration-300': !disabled,
      }"
      :style="{
        '--chip-width': width,
        '--translate-x': translateValue,
        '--rtl-translate-x': `calc(-1 * var(--translate-x))`,
      }"
    />
  </div>
</template>
