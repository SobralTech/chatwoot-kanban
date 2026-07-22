import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationContextMenu from '../Index.vue';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon.vue';

const createStoreMock = () =>
  createStore({
    getters: {
      'labels/getLabels': () => [],
      'teams/getTeams': () => [],
      'inboxAssignableAgents/getUIFlags': () => ({}),
      'inboxAssignableAgents/getAssignableAgents': () => () => [],
      getCurrentUser: () => ({ id: 1, role: 'agent' }),
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'agent',
    },
    actions: {
      'inboxAssignableAgents/fetch': vi.fn(),
      setContextMenuChatId: vi.fn(),
    },
  });

// Mounts (not shallowMount) so the real fluent-icon renders and would
// surface icon-key regressions like the archive/unarchive crash.
const mountMenu = (props = {}) =>
  mount(ConversationContextMenu, {
    props: {
      chatId: 1,
      status: 'open',
      inboxId: 1,
      ...props,
    },
    global: {
      plugins: [createStoreMock()],
      components: { 'fluent-icon': FluentIcon },
    },
  });

describe('ConversationContextMenu archive/unarchive', () => {
  it('renders "Archive conversation" when the conversation is not archived, without throwing', () => {
    let wrapper;
    expect(() => {
      wrapper = mountMenu({ isArchived: false });
    }).not.toThrow();
    expect(wrapper.text()).toContain('Archive conversation');
    expect(wrapper.text()).not.toContain('Unarchive conversation');
  });

  it('renders "Unarchive conversation" when the conversation is archived, without throwing', () => {
    // Regression: rendering this state used to throw
    // "Cannot read properties of undefined (reading 'constructor')" because
    // the unarchive icon key did not exist in the icon set, which prevented
    // the context menu from ever opening for archived conversations.
    let wrapper;
    expect(() => {
      wrapper = mountMenu({ isArchived: true });
    }).not.toThrow();
    expect(wrapper.text()).toContain('Unarchive conversation');
    expect(wrapper.text()).not.toContain('Archive conversation');
  });

  it('places Archive right after Pin, and both after Mute notifications and Mark as read/unread', () => {
    const wrapper = mountMenu({ isArchived: false, hasUnreadMessages: false });
    const labels = wrapper
      .findAll('.menu-label')
      .map(el => el.text())
      .filter(Boolean);

    const markIndex = labels.indexOf('Mark as unread');
    const muteIndex = labels.indexOf('Mute notifications');
    const pinIndex = labels.indexOf('Pin conversation');
    const archiveIndex = labels.indexOf('Archive conversation');

    expect(markIndex).toBeGreaterThanOrEqual(0);
    expect(muteIndex).toBeGreaterThan(markIndex);
    expect(pinIndex).toBeGreaterThan(muteIndex);
    expect(archiveIndex).toBeGreaterThan(pinIndex);
  });

  it('emits toggleArchive with the chatId and closes the menu', async () => {
    const wrapper = mountMenu({ isArchived: false, chatId: 42 });
    await wrapper.find('.menu').findAll('.menu')[0]; // ensure rendered
    const archiveOption = wrapper
      .findAll('.menu')
      .find(el => el.text() === 'Archive conversation');

    await archiveOption.trigger('click');

    expect(wrapper.emitted('toggleArchive')).toEqual([[{ chatId: 42 }]]);
    expect(wrapper.emitted('close')).toBeTruthy();
  });
});
