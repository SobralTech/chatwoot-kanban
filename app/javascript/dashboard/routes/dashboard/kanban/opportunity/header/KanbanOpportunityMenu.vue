<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Popover from 'dashboard/components-next/popover/Popover.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  cardDisplayId: {
    type: [Number, String],
    required: true,
  },
  openedFromConversation: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'openConversation',
  'openConversationInNewTab',
  'openFunnel',
  'openMove',
  'copyCardId',
  'copyCardLink',
  'removeCard',
]);

const { t } = useI18n();

const hasConversation = computed(() => !!props.card.conversationId);

const openConversation = hide => {
  emit('openConversation', props.card);
  hide?.();
};

const openConversationInNewTab = hide => {
  emit('openConversationInNewTab', props.card);
  hide?.();
};

const openFunnel = hide => {
  emit('openFunnel', props.card);
  hide?.();
};

const openMove = hide => {
  emit('openMove');
  hide?.();
};

const copyCardId = hide => {
  emit('copyCardId', props.card);
  hide?.();
};

const copyCardLink = hide => {
  emit('copyCardLink', props.card);
  hide?.();
};

const removeCard = hide => {
  emit('removeCard', props.card);
  hide?.();
};
</script>

<template>
  <Popover align="end" disable-mobile-view :show-content-border="false">
    <button
      type="button"
      data-testid="kanban-opportunity-more-actions"
      class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :aria-label="t('KANBAN.CARD.ACTIONS_MENU')"
      :title="t('KANBAN.CARD.ACTIONS_MENU')"
    >
      <i class="i-lucide-ellipsis-vertical size-4" />
    </button>

    <template #content="{ hide }">
      <div
        data-testid="kanban-opportunity-actions-menu"
        class="grid min-w-56 gap-1 rounded-lg p-1 text-sm text-n-slate-12"
      >
        <button
          v-if="hasConversation && !openedFromConversation"
          type="button"
          data-testid="kanban-opportunity-open-conversation"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="openConversation(hide)"
        >
          <i class="i-lucide-message-square size-4" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION') }}
        </button>
        <button
          v-if="hasConversation && !openedFromConversation"
          type="button"
          data-testid="kanban-opportunity-open-new-tab"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="openConversationInNewTab(hide)"
        >
          <i class="i-lucide-external-link size-4" />
          {{ t('KANBAN.CARD.OPEN_IN_NEW_TAB') }}
        </button>
        <button
          v-if="openedFromConversation"
          type="button"
          data-testid="kanban-opportunity-open-funnel"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="openFunnel(hide)"
        >
          <i class="i-lucide-panels-top-left size-4" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.OPEN_IN_BOARD') }}
        </button>
        <button
          type="button"
          data-testid="kanban-opportunity-move"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="openMove(hide)"
        >
          <i class="i-lucide-corner-up-right size-4" />
          {{ t('KANBAN.CARD.MOVE_TO') }}
        </button>
        <button
          type="button"
          data-testid="kanban-opportunity-copy-card-id"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="copyCardId(hide)"
        >
          <i class="i-lucide-copy size-4" />
          {{
            t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID_WITH_ID', {
              id: cardDisplayId,
            })
          }}
        </button>
        <button
          type="button"
          data-testid="kanban-opportunity-copy-card-link"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-n-alpha-2"
          @click="copyCardLink(hide)"
        >
          <i class="i-lucide-link size-4" />
          {{ t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_LINK') }}
        </button>
        <div class="my-1 border-t border-n-weak" />
        <button
          type="button"
          data-testid="kanban-opportunity-remove-card"
          class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-n-ruby-11 hover:bg-n-ruby-2"
          :aria-label="t('KANBAN.ACTIONS.REMOVE_CARD')"
          :title="t('KANBAN.ACTIONS.REMOVE_CARD')"
          @click="removeCard(hide)"
        >
          <i class="i-lucide-trash size-4" />
          {{ t('KANBAN.ACTIONS.REMOVE_CARD') }}
        </button>
      </div>
    </template>
  </Popover>
</template>
