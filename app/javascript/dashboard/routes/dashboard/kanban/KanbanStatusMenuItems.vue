<script setup>
import { useI18n } from 'vue-i18n';

import { MENU_OPTION_CLASSES } from './menuClasses';

defineProps({
  // Every menu that offers won/lost keeps the test ids its own specs target.
  testidPrefix: {
    type: String,
    required: true,
  },
  isOpen: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['select']);

const { t } = useI18n();
</script>

<template>
  <template v-if="isOpen">
    <button
      type="button"
      :data-testid="`${testidPrefix}-won`"
      class="text-n-teal-11"
      :class="MENU_OPTION_CLASSES"
      :disabled="disabled"
      @click="$emit('select', 'won')"
    >
      <i class="i-lucide-check-circle-2 size-4" />
      {{ t('KANBAN.CARD.STATUS.MARK_AS_WON') }}
    </button>
    <button
      type="button"
      :data-testid="`${testidPrefix}-lost`"
      class="text-n-ruby-11"
      :class="MENU_OPTION_CLASSES"
      :disabled="disabled"
      @click="$emit('select', 'lost')"
    >
      <i class="i-lucide-x-circle size-4" />
      {{ t('KANBAN.CARD.STATUS.MARK_AS_LOST') }}
    </button>
  </template>

  <button
    v-else
    type="button"
    :data-testid="`${testidPrefix}-reopen`"
    :class="MENU_OPTION_CLASSES"
    :disabled="disabled"
    @click="$emit('select', 'reopen')"
  >
    <i class="i-lucide-rotate-ccw size-4" />
    {{ t('KANBAN.CARD.STATUS.REOPEN_OPPORTUNITY') }}
  </button>
</template>
