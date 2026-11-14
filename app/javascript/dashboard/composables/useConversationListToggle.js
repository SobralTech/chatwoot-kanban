import { inject, ref } from 'vue';

export const CONVERSATION_LIST_TOGGLE = Symbol('conversationListToggle');

const NO_LIST_TOGGLE = ref(null);

/**
 * Exposes the conversation list visibility owned by ConversationView, so the
 * conversation header can collapse/expand the list in both the normal and the
 * embedded (kanban) conversation views.
 */
export const useConversationListToggle = () =>
  inject(CONVERSATION_LIST_TOGGLE, NO_LIST_TOGGLE);
