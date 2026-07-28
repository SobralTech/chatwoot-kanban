import { inject } from 'vue';

export const EMBEDDED_CONVERSATION = Symbol('embeddedConversation');

export const useEmbeddedConversation = () =>
  inject(EMBEDDED_CONVERSATION, null);
