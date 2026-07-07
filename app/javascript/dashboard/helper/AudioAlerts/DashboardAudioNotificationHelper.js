import { showBadgeOnFavicon } from './faviconHelper';
import { initFaviconSwitcher } from './faviconHelper';

import GlobalStore from 'dashboard/store';
import AudioNotificationStore from './AudioNotificationStore';
import WindowVisibilityHelper from './WindowVisibilityHelper';
import { useAlert } from 'dashboard/composables';

const NOTIFICATION_TIME = 30000;
const ALERT_DURATION = 10000;
const ALERT_PATH_PREFIX = '/audio/dashboard/';
const DEFAULT_TONE = 'ding';
const DEFAULT_ALERT_TYPE = 'none';
const AUDIO_NOTIFICATION_TYPES = ['contact_message', 'conversation_mention'];
const LEGACY_AUDIO_ALERT_TYPES = [
  'all',
  'assigned',
  'mine',
  'notme',
  'unassigned',
  'true',
];

const selectedAudioAlertTypes = audioAlertType => {
  const values = Array(audioAlertType).flatMap(value =>
    value.toString().split('+')
  );
  const normalizedValues = values.flatMap(value => {
    if (!value || value === 'none' || value === 'false') return [];
    if (LEGACY_AUDIO_ALERT_TYPES.includes(value)) return ['contact_message'];
    if (AUDIO_NOTIFICATION_TYPES.includes(value)) return [value];

    return [];
  });

  return normalizedValues.length
    ? [...new Set(normalizedValues)]
    : [DEFAULT_ALERT_TYPE];
};

export class DashboardAudioNotificationHelper {
  constructor(store) {
    if (!store) {
      throw new Error('store is required');
    }
    this.store = new AudioNotificationStore(store);

    this.notificationConfig = {
      audioAlertType: [DEFAULT_ALERT_TYPE],
      playAlertOnlyWhenHidden: true,
      alertIfUnreadConversationExist: false,
    };

    this.recurringNotificationTimer = null;

    this.audioConfig = {
      audio: null,
      tone: DEFAULT_TONE,
      hasSentSoundPermissionsRequest: false,
    };

    this.currentUser = null;
  }

  intializeAudio = () => {
    const resourceUrl = `${ALERT_PATH_PREFIX}${this.audioConfig.tone}.mp3`;
    this.audioConfig.audio = new Audio(resourceUrl);
    return this.audioConfig.audio.load();
  };

  playAudioAlert = async () => {
    try {
      await this.audioConfig.audio.play();
    } catch (error) {
      if (
        error.name === 'NotAllowedError' &&
        !this.audioConfig.hasSentSoundPermissionsRequest
      ) {
        this.audioConfig.hasSentSoundPermissionsRequest = true;
        useAlert(
          'PROFILE_SETTINGS.FORM.AUDIO_NOTIFICATIONS_SECTION.SOUND_PERMISSION_ERROR',
          { usei18n: true, duration: ALERT_DURATION }
        );
      }
    }
  };

  set = ({
    currentUser,
    alwaysPlayAudioAlert,
    alertIfUnreadConversationExist,
    audioAlertType = DEFAULT_ALERT_TYPE,
    audioAlertTone = DEFAULT_TONE,
  }) => {
    this.notificationConfig = {
      ...this.notificationConfig,
      audioAlertType: selectedAudioAlertTypes(audioAlertType),
      playAlertOnlyWhenHidden: !alwaysPlayAudioAlert,
      alertIfUnreadConversationExist: alertIfUnreadConversationExist,
    };

    this.currentUser = currentUser;

    const previousAudioTone = this.audioConfig.tone;
    this.audioConfig = {
      ...this.audioConfig,
      tone: audioAlertTone,
    };

    if (!this.audioConfig.audio || previousAudioTone !== audioAlertTone) {
      this.intializeAudio();
    }

    initFaviconSwitcher();
    this.clearRecurringTimer();
    this.playAudioEvery30Seconds();
  };

  shouldPlayAlert = () => {
    if (this.notificationConfig.playAlertOnlyWhenHidden) {
      return !WindowVisibilityHelper.isWindowVisible();
    }
    return true;
  };

  executeRecurringNotification = () => {
    if (this.store.hasUnreadConversation() && this.shouldPlayAlert()) {
      this.playAudioAlert();
      showBadgeOnFavicon();
    }
    this.resetRecurringTimer();
  };

  clearRecurringTimer = () => {
    if (this.recurringNotificationTimer) {
      clearTimeout(this.recurringNotificationTimer);
    }
  };

  resetRecurringTimer = () => {
    this.clearRecurringTimer();
    this.recurringNotificationTimer = setTimeout(
      this.executeRecurringNotification,
      NOTIFICATION_TIME
    );
  };

  playAudioEvery30Seconds = () => {
    const { audioAlertType, alertIfUnreadConversationExist } =
      this.notificationConfig;

    if (!audioAlertType.includes('contact_message')) return;
    if (!alertIfUnreadConversationExist) return;

    this.resetRecurringTimer();
  };

  shouldNotifyOnNotification = notification => {
    const { audioAlertType } = this.notificationConfig;
    if (audioAlertType.includes('none')) return false;

    return audioAlertType.includes(notification.notification_type);
  };

  onNotificationCreated = notification => {
    if (!this.currentUser || !this.shouldNotifyOnNotification(notification)) {
      return;
    }

    if (WindowVisibilityHelper.isWindowVisible()) {
      if (this.store.isNotificationFromCurrentConversation(notification)) {
        return;
      }

      if (this.notificationConfig.playAlertOnlyWhenHidden) {
        return;
      }
    }

    this.playAudioAlert();
    showBadgeOnFavicon();

    if (notification.notification_type === 'contact_message') {
      this.playAudioEvery30Seconds();
    }
  };
}

export default new DashboardAudioNotificationHelper(GlobalStore);
