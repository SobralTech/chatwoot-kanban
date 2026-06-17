<script setup>
import { ref } from 'vue';
import { useTrack } from 'dashboard/composables';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { vOnClickOutside } from '@vueuse/components';
import { CAPTAIN_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CopilotMenuBar from './CopilotMenuBar.vue';

const props = defineProps({
  conversationId: { type: Number, default: null },
  disabled: { type: Boolean, default: false },
  isEditorDisabled: { type: Boolean, default: false },
  editorContent: { type: String, default: undefined },
  hasContent: { type: Boolean, default: false },
});

const emit = defineEmits(['executeCopilotAction']);

const { captainTasksEnabled } = useCaptain();
const showCopilotMenu = ref(false);
const copilotToggleRef = ref(null);

const handleCopilotAction = (actionKey, data) => {
  emit('executeCopilotAction', actionKey, data || props.editorContent);
  showCopilotMenu.value = false;
};

const toggleCopilotMenu = () => {
  const isOpening = !showCopilotMenu.value;
  if (isOpening) {
    useTrack(CAPTAIN_EVENTS.EDITOR_AI_MENU_OPENED, {
      conversationId: props.conversationId,
      entryPoint: 'top_panel',
    });
  }
  showCopilotMenu.value = isOpening;
};

const handleClickOutside = () => {
  showCopilotMenu.value = false;
};
</script>

<template>
  <div v-if="captainTasksEnabled" class="relative">
    <NextButton
      ref="copilotToggleRef"
      ghost
      :disabled="disabled || isEditorDisabled"
      :class="{
        'text-n-violet-9 hover:enabled:!bg-n-violet-3': !showCopilotMenu,
        'text-n-violet-9 bg-n-violet-3': showCopilotMenu,
      }"
      sm
      icon="i-ph-sparkle-fill"
      @click="toggleCopilotMenu"
    />
    <CopilotMenuBar
      v-if="showCopilotMenu"
      v-on-click-outside="[handleClickOutside, { ignore: [copilotToggleRef] }]"
      :has-selection="false"
      :has-content="hasContent"
      :conversation-id="conversationId"
      class="ltr:right-0 rtl:left-0 bottom-full mb-2"
      @execute-copilot-action="handleCopilotAction"
    />
  </div>
</template>
