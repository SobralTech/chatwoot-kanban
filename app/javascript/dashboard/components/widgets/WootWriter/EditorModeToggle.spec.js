import { mount } from '@vue/test-utils';
import EditorModeToggle from './EditorModeToggle.vue';
import { REPLY_EDITOR_MODES } from './constants';

describe('EditorModeToggle', () => {
  const createWrapper = (props = {}) =>
    mount(EditorModeToggle, {
      props: {
        mode: REPLY_EDITOR_MODES.REPLY,
        ...props,
      },
      global: {
        mocks: {
          $t: key => {
            const labels = {
              'CONVERSATION.REPLYBOX.REPLY': 'Reply',
              'CONVERSATION.REPLYBOX.PRIVATE_NOTE': 'Private Note',
              'CONVERSATION.REPLYBOX.ASSISTANT': 'Assistant',
            };
            return labels[key] || key;
          },
        },
      },
    });

  it('renders reply, private note and assistant modes', () => {
    const wrapper = createWrapper();

    expect(wrapper.text()).toContain('Reply');
    expect(wrapper.text()).toContain('Private Note');
    expect(wrapper.text()).toContain('Assistant');
  });

  it('emits assistant mode selection', async () => {
    const wrapper = createWrapper();
    const buttons = wrapper.findAll('button');

    await buttons[2].trigger('click');

    expect(wrapper.emitted('setMode')[0]).toEqual([
      REPLY_EDITOR_MODES.ASSISTANT,
    ]);
  });
});
