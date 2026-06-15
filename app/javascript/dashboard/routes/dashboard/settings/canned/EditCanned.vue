<script>
/* eslint no-console: 0 */
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import Modal from '../../../../components/Modal.vue';

export default {
  components: {
    NextButton,
    Modal,
    WootMessageEditor,
    AudioRecorder,
  },
  props: {
    id: { type: Number, default: null },
    edcontent: { type: String, default: '' },
    edshortCode: { type: String, default: '' },
    edmode: { type: String, default: 'insert' },
    edsteps: { type: Array, default: () => [] },
    onClose: { type: Function, default: () => {} },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      editCanned: {
        showAlert: false,
        showLoading: false,
      },
      shortCode: this.edshortCode,
      content: this.edcontent,
      mode: this.edmode || 'insert',
      steps: this.edsteps.length
        ? this.edsteps.map(step => ({
            step_type: step.step_type,
            content: step.content || '',
            file: null,
            file_name: step.file_name || '',
            file_blob_id: step.file_blob_id || '',
          }))
        : [{ step_type: 'text', content: '', file: null }],
      audioRecordFormat: AUDIO_FORMATS.MP3,
      show: true,
    };
  },
  validations: {
    shortCode: {
      required,
      minLength: minLength(2),
    },
    content: {},
  },
  computed: {
    pageTitle() {
      return `${this.$t('CANNED_MGMT.EDIT.TITLE')} - ${this.edshortCode}`;
    },
    isQuickSend() {
      return this.mode === 'quick_send';
    },
    isStepInvalid() {
      if (!this.isQuickSend) return false;

      return this.steps.some(step => {
        if (step.step_type === 'text') return !step.content?.trim();
        return !step.file && !step.file_blob_id;
      });
    },
    isSubmitDisabled() {
      const contentInvalid = !this.isQuickSend && !this.content?.trim();
      return (
        this.v$.shortCode.$invalid ||
        contentInvalid ||
        this.isStepInvalid ||
        this.editCanned.showLoading
      );
    },
  },
  created() {
    this.stepRecorders = {};
  },
  methods: {
    setPageName({ name }) {
      this.v$.content.$touch();
      this.content = name;
    },
    resetForm() {
      this.shortCode = '';
      this.content = '';
      this.mode = 'insert';
      this.steps = [{ step_type: 'text', content: '', file: null }];
      this.v$.shortCode.$reset();
      this.v$.content.$reset();
    },
    addStep(stepType = 'text') {
      this.steps.push({ step_type: stepType, content: '', file: null });
    },
    addRecordingStep() {
      this.steps.push({
        step_type: 'audio',
        content: '',
        file: null,
        isRecording: true,
      });
    },
    removeStep(index) {
      if (this.steps.length === 1) return;
      delete this.stepRecorders[index];
      this.steps.splice(index, 1);
    },
    onStepTypeChange(step) {
      step.content = '';
      step.file = null;
      step.file_name = '';
      step.file_blob_id = '';
      step.isRecording = false;
    },
    onStepFileChange(event, step) {
      const [file] = event.target.files;
      if (!file) return;
      step.file = file;
      step.file_name = file.name || '';
      step.file_blob_id = '';
      step.step_type = file.type.startsWith('audio/') ? 'audio' : 'image';
    },
    setRecorderRef(el, index) {
      if (el) this.stepRecorders[index] = el;
    },
    stopRecording(index) {
      this.stepRecorders[index]?.stopRecording();
    },
    onStepRecordFinish(file, step) {
      step.file = file.file;
      step.file_name = file.name;
      step.file_blob_id = '';
      step.isRecording = false;
    },
    payload() {
      const firstTextStep = this.steps.find(step => step.step_type === 'text');
      return {
        id: this.id,
        short_code: this.shortCode,
        content: this.isQuickSend
          ? firstTextStep?.content || this.shortCode
          : this.content,
        mode: this.mode,
        steps: this.isQuickSend ? this.steps : undefined,
      };
    },
    editCannedResponse() {
      // Show loading on button
      this.editCanned.showLoading = true;
      // Make API Calls
      this.$store
        .dispatch('updateCannedResponse', this.payload())
        .then(() => {
          // Reset Form, Show success message
          this.editCanned.showLoading = false;
          useAlert(this.$t('CANNED_MGMT.EDIT.API.SUCCESS_MESSAGE'));
          this.resetForm();
          setTimeout(() => {
            this.onClose();
          }, 10);
        })
        .catch(error => {
          this.editCanned.showLoading = false;
          const errorMessage =
            error?.message || this.$t('CANNED_MGMT.EDIT.API.ERROR_MESSAGE');
          useAlert(errorMessage);
        });
    },
  },
};
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header :header-title="pageTitle" />
      <form class="flex flex-col w-full" @submit.prevent="editCannedResponse()">
        <div class="w-full">
          <label :class="{ error: v$.shortCode.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.LABEL') }}
            <input
              v-model="shortCode"
              type="text"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.SHORT_CODE.PLACEHOLDER')"
              @input="v$.shortCode.$touch"
            />
          </label>
        </div>

        <div class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.MODE.LABEL') }}
            <select v-model="mode">
              <option value="insert">
                {{ $t('CANNED_MGMT.EDIT.FORM.MODE.INSERT') }}
              </option>
              <option value="quick_send">
                {{ $t('CANNED_MGMT.EDIT.FORM.MODE.QUICK_SEND') }}
              </option>
            </select>
          </label>
        </div>

        <div v-if="!isQuickSend" class="w-full">
          <label :class="{ error: v$.content.$error }">
            {{ $t('CANNED_MGMT.EDIT.FORM.CONTENT.LABEL') }}
          </label>
          <div class="editor-wrap">
            <WootMessageEditor
              v-model="content"
              class="message-editor [&>div]:px-1"
              :class="{ editor_warning: v$.content.$error }"
              channel-type="Context::Default"
              enable-variables
              :enable-canned-responses="false"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.CONTENT.PLACEHOLDER')"
              @blur="v$.content.$touch"
            />
          </div>
        </div>
        <div v-else class="flex flex-col w-full gap-3">
          <label>
            {{ $t('CANNED_MGMT.EDIT.FORM.STEPS.LABEL') }}
          </label>
          <div
            v-for="(step, index) in steps"
            :key="index"
            class="flex flex-col gap-2 p-3 border rounded-md border-n-weak"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm text-n-slate-11">
                {{
                  $t('CANNED_MGMT.EDIT.FORM.STEPS.ITEM', { number: index + 1 })
                }}
              </span>
              <NextButton
                v-if="steps.length > 1"
                faded
                slate
                sm
                type="button"
                :label="$t('CANNED_MGMT.EDIT.FORM.STEPS.REMOVE')"
                @click.prevent="removeStep(index)"
              />
            </div>
            <select v-model="step.step_type" @change="onStepTypeChange(step)">
              <option value="text">
                {{ $t('CANNED_MGMT.EDIT.FORM.STEPS.TEXT') }}
              </option>
              <option value="image">
                {{ $t('CANNED_MGMT.EDIT.FORM.STEPS.IMAGE') }}
              </option>
              <option value="audio">
                {{ $t('CANNED_MGMT.EDIT.FORM.STEPS.AUDIO') }}
              </option>
            </select>
            <textarea
              v-if="step.step_type === 'text'"
              v-model="step.content"
              rows="3"
              :placeholder="$t('CANNED_MGMT.EDIT.FORM.STEPS.TEXT_PLACEHOLDER')"
            />
            <div
              v-else-if="step.step_type === 'audio' && step.isRecording"
              class="flex flex-col gap-2"
            >
              <AudioRecorder
                :ref="el => setRecorderRef(el, index)"
                :audio-record-format="audioRecordFormat"
                @finish-record="file => onStepRecordFinish(file, step)"
              />
              <NextButton
                faded
                slate
                sm
                type="button"
                :label="$t('CANNED_MGMT.EDIT.FORM.STEPS.STOP_RECORDING')"
                @click.prevent="stopRecording(index)"
              />
            </div>
            <input
              v-else
              type="file"
              accept="image/*,audio/*"
              @change="onStepFileChange($event, step)"
            />
            <span v-if="step.file_name" class="text-xs text-n-slate-11">
              {{ step.file_name }}
            </span>
          </div>
          <div class="flex gap-2">
            <NextButton
              faded
              slate
              type="button"
              :label="$t('CANNED_MGMT.EDIT.FORM.STEPS.ADD_TEXT')"
              @click.prevent="addStep('text')"
            />
            <NextButton
              faded
              slate
              type="button"
              :label="$t('CANNED_MGMT.EDIT.FORM.STEPS.ADD_ATTACHMENT')"
              @click.prevent="addStep('image')"
            />
            <NextButton
              faded
              slate
              type="button"
              :label="$t('CANNED_MGMT.EDIT.FORM.STEPS.RECORD_AUDIO')"
              @click.prevent="addRecordingStep"
            />
          </div>
        </div>
        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('CANNED_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="onClose"
          />
          <NextButton
            type="submit"
            :label="$t('CANNED_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="isSubmitDisabled"
            :is-loading="editCanned.showLoading"
          />
        </div>
      </form>
    </div>
  </Modal>
</template>

<style scoped lang="scss">
:deep(.ProseMirror-menubar) {
  @apply hidden;
}

:deep(.ProseMirror-woot-style) {
  @apply min-h-[12.5rem];

  p {
    @apply text-base;
  }
}
</style>
