import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationAssistantPanel from '../ConversationAssistantPanel.vue';
import AssistantMessagesAPI from 'dashboard/api/inbox/assistantMessages';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import enConversationMessages from '../../../../i18n/locale/en/conversation.json';
import ptBRConversationMessages from '../../../../i18n/locale/pt_BR/conversation.json';

vi.mock('dashboard/api/inbox/assistantMessages', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    sendToCustomer: vi.fn(),
  },
}));

vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: {
      value: { conversation_assistant_question_max_length: 2000 },
    },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('ConversationAssistantPanel', () => {
  const assistantMessage = {
    id: 1,
    question: 'Esse toner serve?',
    suggested_reply: 'Sim, esse toner e compativel.',
    internal_note: 'Confirme a revisao do modelo.',
    sources: [{ title: 'Manual', url: 'https://example.com/manual' }],
    status: 'completed',
  };

  const createWrapper = () => {
    const store = createStore({
      getters: {
        'draftMessages/get': () => () => '',
      },
      actions: {
        'draftMessages/set': vi.fn(),
      },
    });

    return mount(ConversationAssistantPanel, {
      props: { conversationId: 12 },
      global: {
        plugins: [store],
        stubs: {
          NextButton: {
            props: ['label', 'disabled', 'isLoading'],
            template:
              '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          },
        },
        mocks: {
          $t: key => key,
        },
      },
    });
  };

  beforeEach(() => {
    AssistantMessagesAPI.get.mockResolvedValue({
      data: {
        payload: [assistantMessage],
        meta: { current_page: 1, total_pages: 1 },
      },
    });
    AssistantMessagesAPI.create.mockResolvedValue({
      data: { ...assistantMessage, id: 2, question: 'Nova pergunta' },
    });
    AssistantMessagesAPI.sendToCustomer.mockResolvedValue({
      data: { ...assistantMessage, sent_message_id: 99, message: { id: 99 } },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('shows assistant input with Ask label instead of Send', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    expect(wrapper.find('textarea').exists()).toBe(true);
    expect(wrapper.text()).toContain('CONVERSATION.ASSISTANT.ASK');
    expect(wrapper.text()).not.toContain('CONVERSATION.REPLYBOX.SEND');
  });

  it('asks through assistant API and never calls conversation message send flow', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper.find('textarea').setValue('Nova pergunta');
    await wrapper.find('form').trigger('submit.prevent');
    await flushPromises();

    expect(AssistantMessagesAPI.create).toHaveBeenCalledWith({
      conversationId: 12,
      question: 'Nova pergunta',
    });
  });

  it('asks the assistant with Enter', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper.find('textarea').setValue('Pergunta pelo enter');
    await wrapper.find('textarea').trigger('keydown.enter');
    await flushPromises();

    expect(AssistantMessagesAPI.create).toHaveBeenCalledWith({
      conversationId: 12,
      question: 'Pergunta pelo enter',
    });
  });

  it('keeps Shift+Enter as a textarea line break', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper.find('textarea').setValue('Linha 1');
    await wrapper.find('textarea').trigger('keydown.enter', { shiftKey: true });
    await flushPromises();

    expect(AssistantMessagesAPI.create).not.toHaveBeenCalled();
  });

  it('copies only the suggested reply', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CONVERSATION.ASSISTANT.COPY')
      .trigger('click');

    expect(copyTextToClipboard).toHaveBeenCalledWith(
      assistantMessage.suggested_reply
    );
  });

  it('emits insertReply with suggested reply without sending', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(
        button => button.text() === 'CONVERSATION.ASSISTANT.INSERT_IN_MESSAGE'
      )
      .trigger('click');

    expect(wrapper.emitted('insertReply')[0]).toEqual([
      assistantMessage.suggested_reply,
    ]);
  });

  it('sends to customer using assistant message id', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    await wrapper
      .findAll('button')
      .find(
        button => button.text() === 'CONVERSATION.ASSISTANT.SEND_TO_CUSTOMER'
      )
      .trigger('click');

    expect(AssistantMessagesAPI.sendToCustomer).toHaveBeenCalledWith({
      conversationId: 12,
      assistantMessageId: assistantMessage.id,
    });
  });

  it('renders sources only inside the assistant panel', async () => {
    const wrapper = createWrapper();
    await flushPromises();

    expect(wrapper.text()).toContain('CONVERSATION.ASSISTANT.SOURCES');
    expect(wrapper.find('a[href="https://example.com/manual"]').exists()).toBe(
      true
    );
  });

  it('does not render sources section when sources are empty', async () => {
    AssistantMessagesAPI.get.mockResolvedValue({
      data: {
        payload: [{ ...assistantMessage, sources: [] }],
        meta: { current_page: 1, total_pages: 1 },
      },
    });
    const wrapper = createWrapper();
    await flushPromises();

    expect(wrapper.text()).not.toContain('CONVERSATION.ASSISTANT.SOURCES');
  });

  it('defines assistant i18n keys in en and pt_BR', () => {
    expect(enConversationMessages.CONVERSATION.REPLYBOX.ASSISTANT).toBeTruthy();
    expect(
      ptBRConversationMessages.CONVERSATION.REPLYBOX.ASSISTANT
    ).toBeTruthy();
  });
});
