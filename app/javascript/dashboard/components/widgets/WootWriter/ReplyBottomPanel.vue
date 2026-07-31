<script>
import { ref } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import FileUpload from 'vue-upload-component';
import * as ActiveStorage from 'activestorage';
import inboxMixin from 'shared/mixins/inboxMixin';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import VideoCallButton from '../VideoCallButton.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';
import CopilotTrigger from './CopilotTrigger.vue';
import { CHAR_LENGTH_WARNING } from './constants';

export default {
  name: 'ReplyBottomPanel',
  components: { NextButton, FileUpload, VideoCallButton, CopilotTrigger },
  mixins: [inboxMixin],
  props: {
    isNote: {
      type: Boolean,
      default: false,
    },
    onSend: {
      type: Function,
      default: () => {},
    },
    onSendAudioRecording: {
      type: Function,
      default: () => {},
    },
    sendButtonText: {
      type: String,
      default: '',
    },
    recordingAudioDurationText: {
      type: String,
      default: '00:00',
    },
    // inbox prop is used in /mixins/inboxMixin,
    // remove this props when refactoring to composable if not needed
    // eslint-disable-next-line vue/no-unused-properties
    inbox: {
      type: Object,
      default: () => ({}),
    },
    showFileUpload: {
      type: Boolean,
      default: false,
    },
    showAudioRecorder: {
      type: Boolean,
      default: false,
    },
    onFileUpload: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorder: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorderPlayPause: {
      type: Function,
      default: () => {},
    },
    isRecordingAudio: {
      type: Boolean,
      default: false,
    },
    recordingAudioState: {
      type: String,
      default: '',
    },
    isSendDisabled: {
      type: Boolean,
      default: false,
    },
    isOnPrivateNote: {
      type: Boolean,
      default: false,
    },
    enableMultipleFileUpload: {
      type: Boolean,
      default: true,
    },
    enableWhatsAppTemplates: {
      type: Boolean,
      default: false,
    },
    enableContentTemplates: {
      type: Boolean,
      default: false,
    },
    conversationId: {
      type: Number,
      required: true,
    },
    message: {
      type: String,
      default: '',
    },
    newConversationModalActive: {
      type: Boolean,
      default: false,
    },
    portalSlug: {
      type: String,
      required: true,
    },
    conversationType: {
      type: String,
      default: '',
    },
    showQuotedReplyToggle: {
      type: Boolean,
      default: false,
    },
    quotedReplyEnabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
    singleLine: {
      type: Boolean,
      default: false,
    },
    copilotDisabled: {
      type: Boolean,
      default: false,
    },
    isMessageLengthReachingThreshold: {
      type: Boolean,
      default: false,
    },
    charactersRemaining: {
      type: Number,
      default: 0,
    },
  },
  emits: [
    'toggleInsertArticle',
    'selectWhatsappTemplate',
    'selectContentTemplate',
    'toggleQuotedReply',
    'executeCopilotAction',
  ],
  setup(props) {
    const { setSignatureFlagForInbox, fetchSignatureFlagFromUISettings } =
      useUISettings();

    const uploadRef = ref(false);

    const keyboardEvents = {
      '$mod+Alt+KeyA': {
        action: () => {
          // Skip if editor is disabled (e.g., WhatsApp 24-hour window expired)
          if (props.isEditorDisabled) return;

          // TODO: This is really hacky, we need to replace the file picker component with
          // a custom one, where the logic and the component markup is isolated.
          // Once we have the custom component, we can remove the hacky logic below.

          const uploadTriggerButton = document.querySelector(
            '#conversationAttachment'
          );
          if (uploadTriggerButton) uploadTriggerButton.click();
        },
        allowOnFocusedInput: true,
      },
    };

    useKeyboardEvents(keyboardEvents);

    return {
      setSignatureFlagForInbox,
      fetchSignatureFlagFromUISettings,
      uploadRef,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      uiFlags: 'integrations/getUIFlags',
    }),
    wrapClass() {
      return {
        'is-note-mode': this.isNote,
        'is-single-line': this.singleLine,
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
    showAttachButton() {
      if (this.isEditorDisabled) return false;
      return this.showFileUpload || this.isNote;
    },
    audioRecorderEligible() {
      if (this.isALineChannel || this.isATiktokChannel) {
        return false;
      }
      // Disable audio recorder for safari browser as recording is not supported
      // const isSafari = /^((?!chrome|android|crios|fxios).)*safari/i.test(
      //   navigator.userAgent
      // );

      return (
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.VOICE_RECORDER
        ) && this.showAudioRecorder
        // !isSafari
      );
    },
    hasContent() {
      return !!this.message && !!this.message.trim().replace(/\n/g, '').length;
    },
    // While idle, the mic/send slot below covers starting a recording.
    // This left-side button only re-appears once recording is in progress,
    // acting as the stop control.
    showAudioRecorderButton() {
      if (this.isEditorDisabled) return false;
      if (!this.isRecordingAudio) return false;
      return this.audioRecorderEligible;
    },
    showMicToggleButton() {
      if (this.isEditorDisabled) return false;
      if (this.isRecordingAudio) return false;
      if (this.hasContent) return false;
      return this.audioRecorderEligible;
    },
    showAudioPlayStopButton() {
      if (this.isEditorDisabled) return false;
      return this.showAudioRecorder && this.isRecordingAudio;
    },
    isInstagramDM() {
      return this.conversationType === 'instagram_direct_message';
    },
    allowedFileTypes() {
      if (this.isOnPrivateNote) {
        return getAllowedFileTypesByChannel();
      }

      let channelType = this.channelType || this.inbox?.channel_type;
      if (this.isAnInstagramChannel || this.isInstagramDM) {
        channelType = INBOX_TYPES.INSTAGRAM;
      }

      return getAllowedFileTypesByChannel({
        channelType,
        medium: this.inbox?.medium,
      });
    },
    enableDragAndDrop() {
      return !this.newConversationModalActive;
    },
    audioRecorderPlayStopIcon() {
      switch (this.recordingAudioState) {
        // playing paused recording stopped inactive destroyed
        case 'playing':
          return 'i-ph-pause';
        case 'paused':
          return 'i-ph-play';
        case 'stopped':
          return 'i-ph-play';
        default:
          return 'i-ph-stop';
      }
    },
    isCapturingAudio() {
      return this.audioRecorderPlayStopIcon === 'i-ph-stop';
    },
    showMessageSignatureButton() {
      if (this.isEditorDisabled) return false;
      return !this.isOnPrivateNote && this.isAnEmailChannel;
    },
    shouldUseLargeActionIcons() {
      return this.singleLine && !this.isAnEmailChannel;
    },
    sendWithSignature() {
      // channelType is sourced from inboxMixin
      return this.fetchSignatureFlagFromUISettings(this.channelType);
    },
    signatureToggleTooltip() {
      return this.sendWithSignature
        ? this.$t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
        : this.$t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP');
    },
    enableInsertArticleInReply() {
      return this.portalSlug;
    },
    isFetchingAppIntegrations() {
      return this.uiFlags.isFetching;
    },
    quotedReplyToggleTooltip() {
      return this.quotedReplyEnabled
        ? this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.DISABLE_TOOLTIP')
        : this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.ENABLE_TOOLTIP');
    },
  },
  mounted() {
    ActiveStorage.start();
  },
  methods: {
    toggleMessageSignature() {
      this.setSignatureFlagForInbox(this.channelType, !this.sendWithSignature);
    },
    toggleInsertArticle() {
      this.$emit('toggleInsertArticle');
    },
  },
};
</script>

<template>
  <div
    class="flex p-3"
    :class="[wrapClass, singleLine ? 'items-center gap-2' : 'justify-between']"
  >
    <div class="left-wrap">
      <FileUpload
        v-if="showAttachButton"
        ref="uploadRef"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
        input-id="conversationAttachment"
        :size="4096 * 4096"
        :accept="allowedFileTypes"
        :multiple="enableMultipleFileUpload"
        :drop="enableDragAndDrop"
        :drop-directory="false"
        :data="{
          direct_upload_url: '/rails/active_storage/direct_uploads',
          direct_upload: true,
        }"
        @input-file="onFileUpload"
      >
        <NextButton
          v-if="showAttachButton"
          v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
          icon="i-ph-paperclip"
          :slate="!shouldUseLargeActionIcons"
          :faded="!shouldUseLargeActionIcons"
          :color="shouldUseLargeActionIcons ? 'slate' : null"
          :variant="shouldUseLargeActionIcons ? 'link' : null"
          :size="shouldUseLargeActionIcons ? 'lg' : 'sm'"
          :class="{ 'compact-action-button': shouldUseLargeActionIcons }"
        />
      </FileUpload>
      <CopilotTrigger
        v-if="singleLine"
        :conversation-id="conversationId"
        :disabled="copilotDisabled"
        :is-editor-disabled="isEditorDisabled"
        :editor-content="message"
        :has-content="hasContent"
        :large-icon-only="shouldUseLargeActionIcons"
        @execute-copilot-action="
          (action, data) => $emit('executeCopilotAction', action, data)
        "
      />
      <NextButton
        v-if="showMessageSignatureButton"
        v-tooltip.top-end="signatureToggleTooltip"
        icon="i-ph-signature"
        slate
        faded
        sm
        @click="toggleMessageSignature"
      />
      <NextButton
        v-if="!singleLine && showQuotedReplyToggle"
        v-tooltip.top-end="quotedReplyToggleTooltip"
        icon="i-ph-quotes"
        :variant="quotedReplyEnabled ? 'solid' : 'faded'"
        color="slate"
        sm
        :aria-pressed="quotedReplyEnabled"
        @click="$emit('toggleQuotedReply')"
      />
      <NextButton
        v-if="!singleLine && enableWhatsAppTemplates"
        v-tooltip.top-end="$t('CONVERSATION.FOOTER.WHATSAPP_TEMPLATES')"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectWhatsappTemplate')"
      />
      <NextButton
        v-if="!singleLine && enableContentTemplates"
        v-tooltip.top-end="'Content Templates'"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectContentTemplate')"
      />
      <VideoCallButton
        v-if="
          !singleLine &&
          (isAWebWidgetInbox || isAPIInbox) &&
          !isOnPrivateNote &&
          !isEditorDisabled
        "
        :conversation-id="conversationId"
      />
      <transition name="modal-fade">
        <div
          v-show="uploadRef && uploadRef.dropActive"
          class="flex fixed top-0 right-0 bottom-0 left-0 z-20 flex-col gap-2 justify-center items-center w-full h-full text-n-slate-12 bg-modal-backdrop-light dark:bg-modal-backdrop-dark"
        >
          <fluent-icon icon="cloud-backup" size="40" />
          <h4 class="text-2xl break-words text-n-slate-12">
            {{ $t('CONVERSATION.REPLYBOX.DRAG_DROP') }}
          </h4>
        </div>
      </transition>
      <NextButton
        v-if="!singleLine && enableInsertArticleInReply"
        v-tooltip.top-end="$t('HELP_CENTER.ARTICLE_SEARCH.OPEN_ARTICLE_SEARCH')"
        icon="i-ph-article-ny-times"
        slate
        faded
        sm
        @click="toggleInsertArticle"
      />
    </div>
    <slot />
    <div
      v-if="singleLine && isMessageLengthReachingThreshold"
      class="text-xs whitespace-nowrap"
    >
      <span :class="charLengthClass">{{ characterLengthWarning }}</span>
    </div>
    <div class="right-wrap">
      <NextButton
        v-if="showAudioRecorderButton"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.CANCEL_AUDIO_RECORDING')"
        icon="i-ph-trash"
        slate
        faded
        sm
        class="hover:!text-n-ruby-9 hover:!bg-n-ruby-3"
        @click="toggleAudioRecorder"
      />
      <NextButton
        v-if="showAudioPlayStopButton"
        :icon="audioRecorderPlayStopIcon"
        :color="isCapturingAudio ? 'ruby' : 'slate'"
        :variant="isCapturingAudio ? 'solid' : 'faded'"
        sm
        :label="recordingAudioDurationText"
        @click="toggleAudioRecorderPlayPause"
      />
      <NextButton
        v-if="showAudioRecorderButton && isCapturingAudio"
        v-tooltip.top-end="sendButtonText"
        icon="i-ph-paper-plane-right-fill"
        color="blue"
        sm
        :label="singleLine ? undefined : sendButtonText"
        @click="onSendAudioRecording"
      />
      <NextButton
        v-else-if="showMicToggleButton"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        icon="i-ph-microphone"
        :variant="shouldUseLargeActionIcons ? 'link' : null"
        :size="shouldUseLargeActionIcons ? 'lg' : 'sm'"
        :color="isNote ? 'amber' : 'blue'"
        :class="{ 'compact-action-button': shouldUseLargeActionIcons }"
        @click="toggleAudioRecorder"
      />
      <NextButton
        v-else
        v-tooltip.top-end="singleLine ? sendButtonText : undefined"
        :icon="singleLine ? 'i-ph-paper-plane-right-fill' : undefined"
        :label="singleLine ? undefined : sendButtonText"
        :variant="shouldUseLargeActionIcons ? 'link' : null"
        type="submit"
        :size="shouldUseLargeActionIcons ? 'lg' : 'sm'"
        :color="isNote ? 'amber' : 'blue'"
        :disabled="isSendDisabled"
        class="flex-shrink-0"
        :class="{ 'compact-action-button': shouldUseLargeActionIcons }"
        @click="onSend"
      />
    </div>
  </div>
</template>

<style lang="scss" scoped>
.left-wrap {
  @apply items-center flex gap-2 flex-shrink-0;
}

.right-wrap {
  @apply flex items-center gap-2 flex-shrink-0;
}

.compact-action-button {
  width: 2.25rem !important;
  height: 2.25rem !important;
  padding: 0 !important;
  font-size: 1.25rem !important;
  background-color: transparent !important;

  &:hover:enabled,
  &:focus-visible:enabled,
  &:active:enabled {
    background-color: transparent !important;
  }
}

:deep(.file-uploads) {
  label {
    @apply cursor-pointer;
  }

  &:hover button {
    @apply enabled:bg-n-slate-9/20;
  }
}

:deep(.file-uploads:hover .compact-action-button) {
  @apply enabled:!bg-transparent;
}
</style>
