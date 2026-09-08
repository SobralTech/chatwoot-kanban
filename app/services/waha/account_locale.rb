# Every user-visible string this integration writes into a message — a media
# placeholder, a poll rendered as text, a call activity — is persisted at write
# time, and these run in Sidekiq, where I18n.locale is the process default
# rather than anything the account chose. Wrapping the work in the account's
# locale is what makes those strings come out in the language the inbox is
# actually read in.
module Waha::AccountLocale
  module_function

  def with(channel, &)
    I18n.with_locale(channel&.account&.locale.presence || I18n.default_locale, &)
  end
end
