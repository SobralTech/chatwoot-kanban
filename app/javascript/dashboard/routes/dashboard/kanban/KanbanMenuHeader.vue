<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  title: {
    type: String,
    required: true,
  },
  showBack: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['back', 'close']);

const { t } = useI18n();
</script>

<template>
  <header class="flex items-center border-b border-n-weak px-2 py-2">
    <button
      v-if="showBack"
      type="button"
      class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
      :aria-label="t('KANBAN.MENU.BACK')"
      @click="$emit('back')"
    >
      <i class="i-lucide-chevron-left size-4" />
    </button>
    <span v-else class="size-8" />
    <h2 class="min-w-0 flex-1 truncate text-center text-sm font-semibold">
      {{ title }}
    </h2>
    <button
      type="button"
      class="flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2"
      :aria-label="t('KANBAN.MENU.CLOSE')"
      @click="$emit('close')"
    >
      <i class="i-lucide-x size-4" />
    </button>
  </header>
</template>
