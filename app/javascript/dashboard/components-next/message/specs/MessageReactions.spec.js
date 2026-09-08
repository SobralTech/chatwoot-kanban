import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import MessageReactions from '../MessageReactions.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('MessageReactions', () => {
  it('groups reactions into chips, exposes authors, and removes my reaction on click', async () => {
    const dispatch = vi.fn().mockResolvedValue(undefined);
    const wrapper = mount(MessageReactions, {
      props: {
        messageId: 7,
        conversationId: 8,
        reactions: {
          me: { emoji: '👍', name: 'You' },
          '5511@c.us': { emoji: '👍', name: 'Ana' },
          '5522@c.us': { emoji: '❤️', name: 'Rui' },
        },
      },
      global: {
        plugins: [createStore({ actions: { reactWahaMessage: dispatch } })],
        directives: { tooltip: () => {} },
      },
    });

    const chips = wrapper.findAll('button, span.inline-flex');
    expect(chips).toHaveLength(2);
    expect(chips[0].text()).toContain('👍');
    expect(chips[0].text()).toContain('2');
    expect(chips[0].attributes('aria-label')).toBeUndefined();
    expect(wrapper.findAll('button')).toHaveLength(1);
    expect(wrapper.text()).not.toContain('message');

    await chips[0].trigger('click');
    expect(dispatch).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 8,
      messageId: 7,
      emoji: '',
    });
  });
});
