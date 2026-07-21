<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  reactions: { type: Object, required: true },
  messageId: { type: Number, required: true },
  conversationId: { type: Number, required: true },
});

const store = useStore();
const { t } = useI18n();
const isRemoving = ref(false);

// Aggregates the per-reactor map into one chip per emoji (`❤️2 👍`), counting
// only when more than one person reacted. The tooltip lists reactor names; the
// "me" slot name is already resolved at event time (agent name or "Você").
const chips = computed(() => {
  const byEmoji = {};
  Object.entries(props.reactions).forEach(([reactorKey, entry]) => {
    const { emoji, name } = entry;
    if (!byEmoji[emoji]) {
      byEmoji[emoji] = { emoji, names: [], isMine: false };
    }
    byEmoji[emoji].names.push(name);
    if (reactorKey === 'me') byEmoji[emoji].isMine = true;
  });
  return Object.values(byEmoji);
});

// Clicking the chip holding our own reaction removes it on WhatsApp; the chip
// disappears when the message.reaction webhook round-trips back.
const removeOwnReaction = async chip => {
  if (!chip.isMine || isRemoving.value) return;
  isRemoving.value = true;
  try {
    await store.dispatch('reactWahaMessage', {
      conversationId: props.conversationId,
      messageId: props.messageId,
      emoji: '',
    });
  } catch (error) {
    useAlert(t('CONVERSATION.CONTEXT_MENU.WAHA_REACT.ERROR'));
  } finally {
    isRemoving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-wrap gap-1">
    <component
      :is="chip.isMine ? 'button' : 'span'"
      v-for="chip in chips"
      :key="chip.emoji"
      v-tooltip.top="chip.names.join(', ')"
      class="inline-flex items-center gap-0.5 rounded-full border border-n-weak bg-n-solid-2 px-1.5 py-px text-sm shadow-sm"
      :class="{ 'hover:bg-n-alpha-2': chip.isMine }"
      @click="removeOwnReaction(chip)"
    >
      {{ chip.emoji }}
      <span v-if="chip.names.length > 1" class="text-xs text-n-slate-11">
        {{ chip.names.length }}
      </span>
    </component>
  </div>
</template>
