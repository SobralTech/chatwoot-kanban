import enConversationMessages from 'dashboard/i18n/locale/en/conversation.json';
import ptBRConversationMessages from 'dashboard/i18n/locale/pt_BR/conversation.json';

describe('conversation access control i18n', () => {
  it('defines access control i18n keys in en and pt_BR', () => {
    const requiredKeys = [
      'LABEL',
      'ALL_AGENTS',
      'ADMINS_ONLY',
      'REVOKED_AGENT_TITLE',
      'CONVERSATION_UNAVAILABLE',
    ];

    requiredKeys.forEach(key => {
      expect(
        enConversationMessages.CONVERSATION.ACCESS_CONTROL[key]
      ).toBeTruthy();
      expect(
        ptBRConversationMessages.CONVERSATION.ACCESS_CONTROL[key]
      ).toBeTruthy();
    });
  });

  it('defines access mode toggle i18n keys in en and pt_BR', () => {
    const requiredModeKeys = ['ALL_AGENTS', 'ADMINS_ONLY'];

    requiredModeKeys.forEach(key => {
      expect(
        enConversationMessages.CONVERSATION.ACCESS_CONTROL.MODE[key]
      ).toBeTruthy();
      expect(
        ptBRConversationMessages.CONVERSATION.ACCESS_CONTROL.MODE[key]
      ).toBeTruthy();
    });
  });
});
