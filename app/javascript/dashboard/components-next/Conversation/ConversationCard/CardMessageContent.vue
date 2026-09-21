<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const { getPlainText } = useMessageFormatter();

const ATTACHMENT_ICONS = {
  image: 'i-lucide-image',
  audio: 'i-lucide-headphones',
  video: 'i-lucide-video',
  file: 'i-lucide-file',
  location: 'i-lucide-map-pin',
  contact: 'i-lucide-contact',
  ig_reel: 'i-lucide-clapperboard',
  embed: 'i-lucide-code',
  fallback: 'i-lucide-link-2',
};

const message = computed(() => props.conversation.lastNonActivityMessage);

const text = computed(() => {
  const { email: { subject } = {} } = props.conversation.customAttributes || {};
  return getPlainText(subject || message.value?.content || '');
});

const attachmentType = computed(() => {
  if (message.value?.contentType === 'sticker') return 'image';
  if (text.value) return null;
  const fileType = message.value?.attachments?.[0]?.fileType;
  if (!fileType) return null;
  return ATTACHMENT_ICONS[fileType] ? fileType : 'file';
});
</script>

<template>
  <span v-if="attachmentType" class="inline-flex items-center gap-1 min-w-0">
    <Icon
      :icon="ATTACHMENT_ICONS[attachmentType]"
      class="flex-shrink-0 size-3.5 text-n-slate-11"
    />
    <span class="truncate">
      {{ t(`CHAT_LIST.ATTACHMENTS.${attachmentType}.CONTENT`) }}
    </span>
  </span>
  <template v-else>{{ text || t('CHAT_LIST.NO_CONTENT') }}</template>
</template>
