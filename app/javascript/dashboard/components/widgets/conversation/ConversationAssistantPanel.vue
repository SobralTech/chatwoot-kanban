<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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

const QUESTION_MAX_LENGTH = 2000;

const messages = ref([]);
const question = ref('');
const isLoading = ref(false);
const isFetching = ref(false);
const error = ref('');

const charactersRemaining = computed(
  () => QUESTION_MAX_LENGTH - question.value.length
);

const isAskDisabled = computed(() => {
  return (
    isLoading.value ||
    !question.value.trim() ||
    question.value.length > QUESTION_MAX_LENGTH
  );
});

const fetchMessages = async () => {
  isFetching.value = true;
  try {
    const { data } = await AssistantMessagesAPI.get(props.conversationId);
    messages.value = data;
  } catch (e) {
    error.value = t('CONVERSATION.ASSISTANT.LOAD_ERROR');
  } finally {
    isFetching.value = false;
  }
};

const askAssistant = async () => {
  if (isAskDisabled.value) return;

  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await AssistantMessagesAPI.create({
      conversationId: props.conversationId,
      question: question.value.trim(),
    });
    messages.value = [...messages.value, data];
    question.value = '';
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

onMounted(fetchMessages);
</script>

<template>
  <div class="px-3 pb-3 space-y-3">
    <div v-if="isFetching" class="text-sm text-n-slate-11">
      {{ t('CONVERSATION.ASSISTANT.LOADING') }}
    </div>

    <div v-if="error" class="text-sm text-n-ruby-9">
      {{ error }}
    </div>

    <div v-if="messages.length" class="space-y-3 max-h-72 overflow-y-auto">
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
    </div>

    <form class="space-y-2" @submit.prevent="askAssistant">
      <textarea
        v-model="question"
        class="w-full min-h-24 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        :placeholder="t('CONVERSATION.ASSISTANT.PLACEHOLDER')"
        @keydown.enter="handleQuestionKeydown"
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
