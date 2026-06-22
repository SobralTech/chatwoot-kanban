<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import AssistantMessagesAPI from 'dashboard/api/inbox/assistantMessages';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['insertReply', 'sentToCustomer']);
const { t } = useI18n();
const { currentAccount } = useAccount();
const store = useStore();

const QUESTION_MAX_LENGTH = computed(
  () => currentAccount.value?.conversation_assistant_question_max_length || 2000
);

const questionDraftKey = `draft-assistant-question-${props.conversationId}`;

const messages = ref([]);
const question = ref(
  store.getters['draftMessages/get'](questionDraftKey) || ''
);
const isLoading = ref(false);
const isFetching = ref(false);
const isLoadingMore = ref(false);
const currentPage = ref(1);
const totalPages = ref(1);
const error = ref('');
const messagesContainer = ref(null);
const textareaRef = ref(null);

const hasMoreMessages = computed(() => currentPage.value < totalPages.value);

const adjustTextareaHeight = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${el.scrollHeight}px`;
};

const scrollToBottom = () => {
  nextTick(() => {
    const container = messagesContainer.value;
    if (container) container.scrollTop = container.scrollHeight;
  });
};

const charactersRemaining = computed(
  () => QUESTION_MAX_LENGTH.value - question.value.length
);

const isAskDisabled = computed(() => {
  return (
    isLoading.value ||
    !question.value.trim() ||
    question.value.length > QUESTION_MAX_LENGTH.value
  );
});

const saveQuestionDraft = () => {
  store.dispatch('draftMessages/set', {
    key: questionDraftKey,
    message: question.value,
  });
};

const debouncedSaveQuestionDraft = debounce(saveQuestionDraft, 500, true);

watch(question, () => {
  debouncedSaveQuestionDraft();
  nextTick(adjustTextareaHeight);
});

onBeforeUnmount(() => {
  saveQuestionDraft();
});

const fetchMessages = async () => {
  isFetching.value = true;
  try {
    const { data } = await AssistantMessagesAPI.get(props.conversationId);
    messages.value = data.payload;
    currentPage.value = data.meta.current_page;
    totalPages.value = data.meta.total_pages;
    scrollToBottom();
  } catch (e) {
    error.value = t('CONVERSATION.ASSISTANT.LOAD_ERROR');
  } finally {
    isFetching.value = false;
  }
};

const loadMoreMessages = async () => {
  if (isLoadingMore.value || !hasMoreMessages.value) return;

  isLoadingMore.value = true;
  const container = messagesContainer.value;
  const previousScrollHeight = container?.scrollHeight || 0;

  try {
    const { data } = await AssistantMessagesAPI.get(
      props.conversationId,
      currentPage.value + 1
    );
    messages.value = [...data.payload, ...messages.value];
    currentPage.value = data.meta.current_page;
    totalPages.value = data.meta.total_pages;

    nextTick(() => {
      if (container) {
        container.scrollTop = container.scrollHeight - previousScrollHeight;
      }
    });
  } catch (e) {
    error.value = t('CONVERSATION.ASSISTANT.LOAD_ERROR');
  } finally {
    isLoadingMore.value = false;
  }
};

const askAssistant = async () => {
  if (isAskDisabled.value) return;

  isLoading.value = true;
  error.value = '';
  scrollToBottom();
  try {
    const { data } = await AssistantMessagesAPI.create({
      conversationId: props.conversationId,
      question: question.value.trim(),
    });
    messages.value = [...messages.value, data];
    question.value = '';
    saveQuestionDraft();
    scrollToBottom();
  } catch (e) {
    error.value =
      e?.response?.data?.error || t('CONVERSATION.ASSISTANT.ASK_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const handleQuestionKeydown = event => {
  if (event.shiftKey) return;

  event.preventDefault();
  askAssistant();
};

const copyReply = async message => {
  await copyTextToClipboard(message.suggested_reply || '');
  useAlert(t('CONVERSATION.ASSISTANT.COPIED'));
};

const insertReply = message => {
  emit('insertReply', message.suggested_reply || '');
};

const sendToCustomer = async message => {
  try {
    const { data } = await AssistantMessagesAPI.sendToCustomer({
      conversationId: props.conversationId,
      assistantMessageId: message.id,
    });
    messages.value = messages.value.map(item =>
      item.id === data.id ? data : item
    );
    emit('sentToCustomer', data.message);
    useAlert(t('CONVERSATION.ASSISTANT.SENT_TO_CUSTOMER'));
  } catch (e) {
    useAlert(
      e?.response?.data?.error ||
        t('CONVERSATION.ASSISTANT.SEND_TO_CUSTOMER_ERROR')
    );
  }
};

onMounted(() => {
  fetchMessages();
  nextTick(adjustTextareaHeight);
});
</script>

<template>
  <div class="flex max-h-[28rem] flex-col px-3 pt-3 pb-3 space-y-3">
    <div v-if="isFetching" class="text-sm text-n-slate-11">
      {{ t('CONVERSATION.ASSISTANT.LOADING') }}
    </div>

    <div v-if="error" class="text-sm text-n-ruby-9">
      {{ error }}
    </div>

    <div
      v-if="messages.length || isLoading"
      ref="messagesContainer"
      class="min-h-0 flex-1 space-y-3 overflow-y-auto"
    >
      <div v-if="hasMoreMessages" class="flex justify-center">
        <NextButton
          slate
          faded
          sm
          :is-loading="isLoadingMore"
          :label="t('CONVERSATION.ASSISTANT.LOAD_MORE')"
          @click="loadMoreMessages"
        />
      </div>

      <div
        v-for="message in messages"
        :key="message.id"
        class="rounded-lg border border-n-weak p-3 space-y-3"
      >
        <div class="text-xs font-medium text-n-slate-11">
          {{ t('CONVERSATION.ASSISTANT.QUESTION_LABEL') }}
        </div>
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
          {{ message.question }}
        </p>

        <template
          v-if="
            message.status === 'completed' ||
            message.status === 'sent_to_customer'
          "
        >
          <div>
            <div class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION.ASSISTANT.SUGGESTED_REPLY') }}
            </div>
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
              {{ message.suggested_reply }}
            </p>
          </div>

          <div v-if="message.internal_note">
            <div class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION.ASSISTANT.INTERNAL_NOTE') }}
            </div>
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
              {{ message.internal_note }}
            </p>
          </div>

          <div v-if="message.sources && message.sources.length">
            <div class="text-xs font-medium text-n-slate-11">
              {{ t('CONVERSATION.ASSISTANT.SOURCES') }}
            </div>
            <ul class="text-sm list-disc ltr:pl-4 rtl:pr-4">
              <li v-for="source in message.sources" :key="source.url">
                <a
                  class="text-n-blue-10 hover:underline"
                  :href="source.url"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{ source.title || source.url }}
                </a>
              </li>
            </ul>
          </div>

          <div class="flex flex-wrap gap-2">
            <NextButton
              slate
              faded
              sm
              :label="t('CONVERSATION.ASSISTANT.COPY')"
              @click="copyReply(message)"
            />
            <NextButton
              slate
              faded
              sm
              :label="t('CONVERSATION.ASSISTANT.INSERT_IN_MESSAGE')"
              @click="insertReply(message)"
            />
            <NextButton
              sm
              color="blue"
              :disabled="!!message.sent_message_id"
              :label="
                message.sent_message_id
                  ? t('CONVERSATION.ASSISTANT.SENT')
                  : t('CONVERSATION.ASSISTANT.SEND_TO_CUSTOMER')
              "
              @click="sendToCustomer(message)"
            />
          </div>
        </template>

        <p v-else class="text-sm text-n-ruby-9">
          {{ message.internal_note || t('CONVERSATION.ASSISTANT.ASK_ERROR') }}
        </p>
      </div>

      <div
        v-if="isLoading"
        class="flex items-center gap-2 rounded-lg border border-n-weak p-3"
      >
        <span class="text-sm text-n-slate-11">
          {{ t('CONVERSATION.ASSISTANT.THINKING') }}
        </span>
        <span class="flex items-center gap-1">
          <span
            class="h-1.5 w-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:-0.3s]"
          />
          <span
            class="h-1.5 w-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:-0.15s]"
          />
          <span class="h-1.5 w-1.5 rounded-full bg-n-slate-9 animate-bounce" />
        </span>
      </div>
    </div>

    <form class="flex-shrink-0 space-y-2" @submit.prevent="askAssistant">
      <textarea
        ref="textareaRef"
        v-model="question"
        rows="1"
        class="assistant-question-input w-full resize-none rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        :placeholder="t('CONVERSATION.ASSISTANT.PLACEHOLDER')"
        @keydown.enter="handleQuestionKeydown"
        @input="adjustTextareaHeight"
      />
      <div class="flex items-center justify-between gap-2">
        <span
          class="text-xs"
          :class="charactersRemaining < 0 ? 'text-n-ruby-9' : 'text-n-slate-11'"
        >
          {{ charactersRemaining }}
          {{ t('CONVERSATION.ASSISTANT.CHARACTERS_REMAINING') }}
        </span>
        <NextButton
          type="submit"
          sm
          color="blue"
          :is-loading="isLoading"
          :disabled="isAskDisabled"
          :label="t('CONVERSATION.ASSISTANT.ASK')"
        />
      </div>
    </form>
  </div>
</template>

<style lang="scss" scoped>
.assistant-question-input {
  min-height: 5rem;
  max-height: 142px;
  overflow-y: auto;
}
</style>
