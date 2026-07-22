import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const mockPush = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: '1' },
  }),
  useRouter: () => ({
    push: mockPush,
  }),
}));

const baseInbox = {
  id: 2,
  name: 'Support',
  channelType: 'Channel::Email',
};

const baseContact = {
  id: 5,
  name: 'Jane Doe',
  thumbnail: '',
  availabilityStatus: 'online',
};

const mountCard = (conversation = {}) =>
  shallowMount(ConversationCard, {
    props: {
      conversation: { id: 1, priority: null, labels: [], ...conversation },
      contact: baseContact,
      stateInbox: baseInbox,
      accountLabels: [],
    },
    global: {
      stubs: {
        Icon: {
          props: ['icon'],
          template: '<i :data-icon="icon" />',
        },
      },
    },
  });

describe('ConversationCard', () => {
  beforeEach(() => {
    mockPush.mockClear();
  });

  describe('archived indicator', () => {
    it('shows the archive icon with a tooltip when the conversation is archived', () => {
      const wrapper = mountCard({ archivedAt: 1752230400 });

      const archiveIcon = wrapper.find('[data-icon="i-lucide-archive"]');
      expect(archiveIcon.exists()).toBe(true);
      expect(archiveIcon.attributes('data-icon')).toBe('i-lucide-archive');
    });

    it('does not show the archive icon for a non-archived conversation', () => {
      const wrapper = mountCard({ archivedAt: null });

      expect(wrapper.find('[data-icon="i-lucide-archive"]').exists()).toBe(
        false
      );
    });
  });

  describe('onCardClick navigation', () => {
    it('navigates to the archived conversation route when the conversation is archived', async () => {
      const wrapper = mountCard({ archivedAt: 1752230400 });

      await wrapper.find('[role="button"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith({
        path: '/app/accounts/1/archived/conversations/1',
      });
    });

    it('navigates to the normal conversation route when the conversation is not archived', async () => {
      const wrapper = mountCard({ archivedAt: null });

      await wrapper.find('[role="button"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith({
        path: '/app/accounts/1/conversations/1',
      });
    });
  });
});
