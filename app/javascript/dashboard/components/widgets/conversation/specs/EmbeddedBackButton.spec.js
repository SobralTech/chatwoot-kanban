import { mount } from '@vue/test-utils';
import { ref } from 'vue';

import EmbeddedBackButton from '../EmbeddedBackButton.vue';
import { EMBEDDED_CONVERSATION } from 'dashboard/composables/useEmbeddedConversation';

describe('EmbeddedBackButton', () => {
  it('navigates back through the embedded conversation context', async () => {
    const goBack = vi.fn();
    const wrapper = mount(EmbeddedBackButton, {
      global: {
        provide: { [EMBEDDED_CONVERSATION]: ref({ goBack }) },
        mocks: { $t: key => key },
        stubs: {
          NextButton: {
            name: 'NextButton',
            template: '<button v-bind="$attrs" />',
          },
        },
      },
    });

    await wrapper
      .get('[data-testid="embedded-conversation-back"]')
      .trigger('click');

    expect(goBack).toHaveBeenCalledTimes(1);
  });
});
