<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import { convertAudio } from './utils/mp3ConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'recordingError',
  'pause',
  'play',
]);

const waveformContainer = ref(null);
const wavesurfer = ref(null);
const record = ref(null);
const isRecording = ref(false);
const isPlaying = ref(false);
const hasRecording = ref(false);

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const initWaveSurfer = () => {
  wavesurfer.value = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create({
        scrollingWaveform: true,
        renderRecordedAudio: false,
      }),
    ],
  });

  wavesurfer.value.on('pause', () => emit('pause'));
  wavesurfer.value.on('play', () => emit('play'));

  record.value = wavesurfer.value.plugins[0];

  wavesurfer.value.on('finish', () => {
    isPlaying.value = false;
  });

  record.value.on('record-end', async blob => {
    const audioUrl = URL.createObjectURL(blob);
    // If MP3/WAV conversion fails (e.g. decodeAudioData can't parse the
    // browser's MediaRecorder output), fall back to the raw blob so the
    // stop button still resolves and the send button becomes usable.
    let audioBlob;
    let mimeType = props.audioRecordFormat;
    let extension = props.audioRecordFormat === 'audio/wav' ? 'wav' : 'mp3';
    try {
      audioBlob = await convertAudio(blob, props.audioRecordFormat);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[AudioRecorder] conversion failed, using raw blob', error);
      audioBlob = blob;
      mimeType = blob.type || 'audio/webm';
      extension = (mimeType.split('/')[1] || 'webm').split(';')[0];
    }
    const fileName = `${getUuid()}.${extension}`;
    const file = new File([audioBlob], fileName, { type: mimeType });
    wavesurfer.value.load(audioUrl);
    emit('finishRecord', {
      name: file.name,
      type: file.type,
      size: file.size,
      file,
    });
    hasRecording.value = true;
    isRecording.value = false;
  });

  record.value.on('record-progress', time => {
    emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => {
  if (isRecording.value) {
    record.value.stopRecording();
    isRecording.value = false;
  }
};

// The record plugin rethrows a plain Error, so the DOMException name from
// getUserMedia is gone; only its message still carries the reason.
const recordingErrorReason = message => {
  if (/permission|not allowed/i.test(message)) return 'permission';
  if (/not found|no device/i.test(message)) return 'noDevice';
  return 'error';
};

const startRecording = async () => {
  // startRecording resolves only once getUserMedia hands over the stream, so a
  // blocked/missing microphone rejects here. Without this the recorder stays
  // open with a dead timer and the failure never reaches the agent.
  try {
    await record.value.startRecording();
    isRecording.value = true;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[AudioRecorder] could not start recording', error);
    emit('recordingError', recordingErrorReason(error.message));
  }
};

const playPause = () => {
  if (hasRecording.value) {
    wavesurfer.value.playPause();
    isPlaying.value = !isPlaying.value;
  }
};

onMounted(() => {
  initWaveSurfer();
  startRecording();
});

onUnmounted(() => {
  // Stop an in-progress recording gracefully first; destroying the
  // instance mid-capture aborts the active media stream and throws an
  // unhandled AbortError from inside wavesurfer's record plugin.
  if (isRecording.value) {
    record.value?.stopRecording();
  }
  wavesurfer.value?.destroy();
});

defineExpose({ playPause, stopRecording, record });
</script>

<template>
  <div ref="waveformContainer" class="w-full p-1" />
</template>
