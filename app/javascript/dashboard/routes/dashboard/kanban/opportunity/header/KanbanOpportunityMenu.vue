<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

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
  'copyCardId',
  'copyCardLink',
  'removeCard',
]);

const { t } = useI18n();
const isOpen = ref(false);
const closeMenu = () => {
  isOpen.value = false;
};

const hasConversation = computed(
  () => !!props.card.conversationId && !props.openedFromConversation
);

const menuSections = computed(() => [
  {
    items: [
      hasConversation.value && {
        action: 'openConversation',
        value: 'openConversation',
        icon: 'i-lucide-message-square',
        label: t('KANBAN.OPPORTUNITY_DETAILS.OPEN_CONVERSATION'),
      },
      hasConversation.value && {
        action: 'openConversationInNewTab',
        value: 'openConversationInNewTab',
        icon: 'i-lucide-external-link',
        label: t('KANBAN.CARD.OPEN_IN_NEW_TAB'),
      },
      props.openedFromConversation && {
        action: 'openFunnel',
        value: 'openFunnel',
        icon: 'i-lucide-panels-top-left',
        label: t('KANBAN.OPPORTUNITY_DETAILS.OPEN_IN_BOARD'),
      },
      {
        action: 'copyCardId',
        value: 'copyCardId',
        icon: 'i-lucide-copy',
        label: t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_ID_WITH_ID', {
          id: props.cardDisplayId,
        }),
      },
      {
        action: 'copyCardLink',
        value: 'copyCardLink',
        icon: 'i-lucide-link',
        label: t('KANBAN.OPPORTUNITY_DETAILS.COPY_CARD_LINK'),
      },
    ].filter(Boolean),
  },
  {
    items: [
      {
        action: 'delete',
        value: 'removeCard',
        icon: 'i-lucide-trash',
        label: t('KANBAN.ACTIONS.REMOVE_CARD'),
      },
    ],
  },
]);

const menuActions = {
  openConversation: () => emit('openConversation', props.card),
  openConversationInNewTab: () => emit('openConversationInNewTab', props.card),
  openFunnel: () => emit('openFunnel', props.card),
  copyCardId: () => emit('copyCardId', props.card),
  copyCardLink: () => emit('copyCardLink', props.card),
  removeCard: () => emit('removeCard', props.card),
};

const onAction = ({ value }) => {
  closeMenu();
  menuActions[value]();
};
</script>

<template>
  <div v-on-click-outside="closeMenu" class="relative flex items-center">
    <button
      type="button"
      data-testid="kanban-opportunity-more-actions"
      class="flex size-8 flex-shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :aria-label="t('KANBAN.CARD.ACTIONS_MENU')"
      :title="t('KANBAN.CARD.ACTIONS_MENU')"
      @click="isOpen = !isOpen"
    >
      <i class="i-lucide-ellipsis-vertical size-4" />
    </button>

    <DropdownMenu
      v-if="isOpen"
      data-testid="kanban-opportunity-actions-menu"
      :menu-sections="menuSections"
      class="top-full mt-1 ltr:right-0 rtl:left-0"
      @action="onAction"
    />
  </div>
</template>
