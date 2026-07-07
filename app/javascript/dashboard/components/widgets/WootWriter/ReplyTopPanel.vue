<script>
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { REPLY_EDITOR_MODES, CHAR_LENGTH_WARNING } from './constants';
import NextButton from 'dashboard/components-next/button/Button.vue';
import EditorModeToggle from './EditorModeToggle.vue';
import CopilotTrigger from './CopilotTrigger.vue';

export default {
  name: 'ReplyTopPanel',
  components: {
    NextButton,
    EditorModeToggle,
    CopilotTrigger,
  },
  props: {
    mode: {
      type: String,
      default: REPLY_EDITOR_MODES.REPLY,
    },
    isAnEmailChannel: {
      type: Boolean,
      default: true,
    },
    isReplyRestricted: {
      type: Boolean,
      default: false,
    },
    showAssistant: {
      type: Boolean,
      default: true,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
    conversationId: {
      type: Number,
      default: null,
    },
    isMessageLengthReachingThreshold: {
      type: Boolean,
      default: () => false,
    },
    charactersRemaining: {
      type: Number,
      default: () => 0,
    },
    editorContent: {
      type: String,
      default: undefined,
    },
    hasContent: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['setReplyMode', 'toggleEditorSize', 'executeCopilotAction'],
  setup(props, { emit }) {
    const setReplyMode = mode => {
      emit('setReplyMode', mode);
    };
    const handleReplyClick = () => {
      if (props.isReplyRestricted) return;
      setReplyMode(REPLY_EDITOR_MODES.REPLY);
    };
    const handleNoteClick = () => {
      setReplyMode(REPLY_EDITOR_MODES.NOTE);
    };
    const { captainTasksEnabled } = useCaptain();

    const keyboardEvents = {
      'Alt+KeyP': {
        action: () => handleNoteClick(),
        allowOnFocusedInput: true,
      },
      'Alt+KeyL': {
        action: () => handleReplyClick(),
        allowOnFocusedInput: true,
      },
    };
    useKeyboardEvents(keyboardEvents);

    return {
      setReplyMode,
      handleReplyClick,
      handleNoteClick,
      REPLY_EDITOR_MODES,
      captainTasksEnabled,
    };
  },
  computed: {
    replyButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.REPLY,
      };
    },
    noteButtonClass() {
      return {
        'is-active': this.mode === REPLY_EDITOR_MODES.NOTE,
      };
    },
    charLengthClass() {
      return this.charactersRemaining < 0 ? 'text-n-ruby-9' : 'text-n-slate-11';
    },
    characterLengthWarning() {
      return this.charactersRemaining < 0
        ? `${-this.charactersRemaining} ${CHAR_LENGTH_WARNING.NEGATIVE}`
        : `${this.charactersRemaining} ${CHAR_LENGTH_WARNING.UNDER_50}`;
    },
  },
};
</script>

<template>
  <div
    class="flex justify-between gap-2 h-[3.25rem] items-center ltr:pl-3 ltr:pr-2 rtl:pr-3 rtl:pl-2"
  >
    <EditorModeToggle
      :mode="mode"
      :disabled="disabled"
      :is-reply-restricted="isReplyRestricted"
      :show-assistant="showAssistant"
      @set-mode="setReplyMode"
    />
    <div v-if="isAnEmailChannel" class="flex items-center mx-4 my-0">
      <div v-if="isMessageLengthReachingThreshold" class="text-xs">
        <span :class="charLengthClass">
          {{ characterLengthWarning }}
        </span>
      </div>
    </div>
    <div
      v-if="isAnEmailChannel && captainTasksEnabled"
      class="flex items-center gap-2"
    >
      <CopilotTrigger
        v-if="mode !== REPLY_EDITOR_MODES.ASSISTANT"
        :conversation-id="conversationId"
        :disabled="disabled"
        :is-editor-disabled="isEditorDisabled"
        :editor-content="editorContent"
        :has-content="hasContent"
        @execute-copilot-action="
          (action, data) => $emit('executeCopilotAction', action, data)
        "
      />
      <NextButton
        ghost
        class="text-n-slate-11"
        sm
        icon="i-lucide-maximize-2"
        @click="$emit('toggleEditorSize')"
      />
    </div>
  </div>
</template>
