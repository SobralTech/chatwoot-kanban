require 'rails_helper'

describe Waha::ContactResolver do
  let(:channel) { create(:channel_waha) }

  def resolver(jid:, push_name: 'Jane Doe', from_me: false, sender_alt: nil, recipient_alt: nil)
    described_class.new(
      channel: channel, jid: jid, push_name: push_name, from_me: from_me,
      sender_alt: sender_alt, recipient_alt: recipient_alt
    )
  end

  describe 'canonical identity resolution (core)' do
    let(:lid) { '111222333@lid' }

    it 'propagates a transient WAHA failure instead of silently falling back to the unresolved LID' do
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/#{lid}")
        .to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { resolver(jid: lid).perform }.to raise_error(CustomExceptions::Waha::TransientError)
      expect(channel.account.contacts.count).to eq(0)
      expect(channel.inbox.contact_inboxes.count).to eq(0)
    end
  end

  describe 'optional enrichment (avatar, contact name)' do
    let(:jid) { '5511888888888@c.us' }

    it 'still creates the contact and contact inbox when the enrichment lookups fail' do
      stub_request(:get, %r{https://waha\.test/api/.*}).to_return(status: 500, body: '{}')

      contact_inbox = resolver(jid: jid, push_name: nil).perform

      expect(contact_inbox).to be_a(ContactInbox)
      expect(contact_inbox.contact.phone_number).to eq('+5511888888888')
      expect(contact_inbox.contact.avatar).not_to be_attached
    end
  end
end
