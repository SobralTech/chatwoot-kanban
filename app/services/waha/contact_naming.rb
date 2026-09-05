# Ranks the name evidence WAHA can give us about a person, so a contact named
# from weaker evidence is upgraded when better data shows up while a fallback
# never overwrites a name we already trust.
module Waha::ContactNaming
  # Recorded on the contact so a later event knows what the current name is
  # worth without having to guess.
  SOURCE_KEY = 'waha_name_source'.freeze

  # Best first — the priority for a direct conversation: the name held by WAHA's
  # own contacts registry (the address book/verified name), the push name the
  # event carried, the formatted phone number and finally the raw JID.
  SOURCES = %w[contact push phone jid].freeze

  # Names we generate ourselves when WAHA gives us nothing: "+5511999999999" or
  # a bare JID. They identify but don't name, so any real name outranks them.
  FALLBACK_NAME = /\A\+\d+\z|@(?:c\.us|lid|s\.whatsapp\.net|g\.us)\z/

  module_function

  def rank(source)
    SOURCES.index(source.to_s) || SOURCES.length
  end

  def better?(source, than:)
    rank(source) < rank(than)
  end

  def fallback_name?(name)
    name.blank? || name.match?(FALLBACK_NAME)
  end

  # The evidence behind a contact's current name: what we recorded when we named
  # it or, for a contact named before we tracked this (or renamed by an agent),
  # whatever the stored name itself reveals.
  def source_of(contact)
    contact.additional_attributes[SOURCE_KEY].presence || (fallback_name?(contact.name) ? 'jid' : 'contact')
  end
end
