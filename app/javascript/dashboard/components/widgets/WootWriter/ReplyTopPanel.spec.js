import { mount } from '@vue/test-utils';
import ReplyTopPanel from './ReplyTopPanel.vue';
import { REPLY_EDITOR_MODES } from './constants';

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: false }),
}));

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

describe('ReplyTopPanel', () => {
  const createWrapper = (props = {}) =>
    mount(ReplyTopPanel, {
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

  it('passes mode selection from editor toggle to reply box', async () => {
    const wrapper = createWrapper();
    const buttons = wrapper.findAll('button');

    await buttons[0].trigger('click');
    await buttons[1].trigger('click');
    await buttons[2].trigger('click');

    expect(wrapper.emitted('setReplyMode')).toEqual([
      [REPLY_EDITOR_MODES.REPLY],
      [REPLY_EDITOR_MODES.NOTE],
      [REPLY_EDITOR_MODES.ASSISTANT],
    ]);
  });
});
