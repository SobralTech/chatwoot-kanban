import { DashboardAudioNotificationHelper } from '../DashboardAudioNotificationHelper';
import WindowVisibilityHelper from '../WindowVisibilityHelper';
import { initFaviconSwitcher, showBadgeOnFavicon } from '../faviconHelper';

vi.mock('../faviconHelper', () => ({
  initFaviconSwitcher: vi.fn(),
  showBadgeOnFavicon: vi.fn(),
}));

vi.mock('../WindowVisibilityHelper', () => ({
  default: {
    isWindowVisible: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

describe('DashboardAudioNotificationHelper', () => {
  let helper;
  let store;

  beforeEach(() => {
    vi.useFakeTimers();
    global.Audio = vi.fn(() => ({
      load: vi.fn(),
      play: vi.fn().mockResolvedValue(),
    }));

    store = {
      getters: {
        getAllStatusChats: vi.fn().mockReturnValue([]),
        getSelectedChat: null,
      },
    };

    helper = new DashboardAudioNotificationHelper(store);
    WindowVisibilityHelper.isWindowVisible.mockReturnValue(false);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('normalizes legacy audio alert values to contact_message', () => {
    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'assigned+unassigned',
    });

    expect(helper.notificationConfig.audioAlertType).toEqual([
      'contact_message',
    ]);
  });

  it('plays audio for enabled notifications', () => {
    const playAudioAlert = vi
      .spyOn(helper, 'playAudioAlert')
      .mockResolvedValue(undefined);

    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'contact_message+conversation_mention',
      alwaysPlayAudioAlert: true,
    });

    helper.onNotificationCreated({
      notification_type: 'conversation_mention',
      primary_actor: { id: 42 },
    });

    expect(playAudioAlert).toHaveBeenCalled();
    expect(showBadgeOnFavicon).toHaveBeenCalled();
  });

  it('does not play audio for the current conversation while visible', () => {
    const playAudioAlert = vi
      .spyOn(helper, 'playAudioAlert')
      .mockResolvedValue(undefined);

    store.getters.getSelectedChat = { id: 42 };
    WindowVisibilityHelper.isWindowVisible.mockReturnValue(true);

    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'contact_message',
      alwaysPlayAudioAlert: true,
    });

    helper.onNotificationCreated({
      notification_type: 'contact_message',
      primary_actor: { id: 42 },
    });

    expect(playAudioAlert).not.toHaveBeenCalled();
  });

  it('does not play audio in an active window when hidden-only is enabled', () => {
    const playAudioAlert = vi
      .spyOn(helper, 'playAudioAlert')
      .mockResolvedValue(undefined);

    WindowVisibilityHelper.isWindowVisible.mockReturnValue(true);

    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'contact_message',
      alwaysPlayAudioAlert: false,
    });

    helper.onNotificationCreated({
      notification_type: 'contact_message',
      primary_actor: { id: 9 },
    });

    expect(playAudioAlert).not.toHaveBeenCalled();
  });

  it('starts the recurring timer only for contact_message alerts', () => {
    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'conversation_mention',
      alertIfUnreadConversationExist: true,
    });

    expect(helper.recurringNotificationTimer).toBeNull();

    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'contact_message',
      alertIfUnreadConversationExist: true,
    });

    expect(helper.recurringNotificationTimer).not.toBeNull();
  });

  it('replays contact_message alerts when unread conversations remain', () => {
    const playAudioAlert = vi
      .spyOn(helper, 'playAudioAlert')
      .mockResolvedValue(undefined);

    store.getters.getAllStatusChats.mockReturnValue([
      { id: 1, unread_count: 2 },
    ]);

    helper.set({
      currentUser: { id: 1 },
      audioAlertType: 'contact_message',
      alertIfUnreadConversationExist: true,
    });

    vi.runOnlyPendingTimers();

    expect(playAudioAlert).toHaveBeenCalled();
    expect(initFaviconSwitcher).toHaveBeenCalled();
  });
});
