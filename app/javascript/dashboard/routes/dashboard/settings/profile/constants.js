export const AUDIO_ALERT_TYPES = [
  {
    label: 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.CONTACT_MESSAGE',
    value: 'contact_message',
  },
  {
    label: 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.CONVERSATION_MENTION',
    value: 'conversation_mention',
  },
];

export const NOTIFICATION_TYPES = [
  ...AUDIO_ALERT_TYPES,
  {
    label: 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.VOICE_CALL_MISSED',
    value: 'voice_call_missed',
  },
];
