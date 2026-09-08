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

    it 'propagates a transient reverse-alias lookup failure before creating a phone contact' do
      jid = '5511888888888@c.us'
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { resolver(jid: jid).perform }.to raise_error(CustomExceptions::Waha::TransientError)
      expect(channel.account.contacts.count).to eq(0)
      expect(channel.inbox.contact_inboxes.count).to eq(0)
    end
  end

  describe 'optional enrichment (avatar, contact name)' do
    let(:jid) { '5511888888888@c.us' }

    it 'still creates the contact and contact inbox when the enrichment lookups fail' do
      stub_request(:get, %r{https://waha\.test/api/.*}).to_return(status: 500, body: '{}')
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 200, body: { lid: nil, pn: jid }.to_json, headers: { 'Content-Type' => 'application/json' })

      contact_inbox = resolver(jid: jid, push_name: nil).perform

      expect(contact_inbox).to be_a(ContactInbox)
      expect(contact_inbox.contact.phone_number).to eq('+5511888888888')
      expect(contact_inbox.contact.avatar).not_to be_attached
    end
  end

  # GOWS answers GET /api/{session}/contacts/{id} with {id, name, pushname}:
  # `name` is the address-book/verified name, `pushname` the WhatsApp profile one.
  describe 'name priority and enrichment' do
    let(:jid) { '5511888888888@c.us' }

    def stub_contact_registry(body)
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/contacts/#{jid}")
        .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    before do
      stub_request(:get, %r{https://waha\.test/api/.*}).to_return(status: 404, body: '{}')
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 200, body: { lid: nil, pn: jid }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    context 'when the contact is new' do
      it 'prefers the contacts registry name over the push name of the event' do
        stub_contact_registry(id: jid, name: 'Maria Silva', pushname: 'mari')

        contact = resolver(jid: jid).perform.contact

        expect(contact).to have_attributes(name: 'Maria Silva', phone_number: '+5511888888888')
        expect(contact.additional_attributes).to include('waha_name_source' => 'contact')
      end

      it 'falls back to the push name of the event when the registry has no address-book name' do
        stub_contact_registry(id: jid, name: nil, pushname: 'mari')

        contact = resolver(jid: jid, push_name: 'Jane Doe').perform.contact

        expect(contact).to have_attributes(name: 'Jane Doe')
        expect(contact.additional_attributes).to include('waha_name_source' => 'push')
      end

      it 'falls back to the formatted phone number when neither the registry nor the event names the contact' do
        stub_contact_registry(id: jid, name: nil, pushname: nil)

        contact = resolver(jid: jid, push_name: nil).perform.contact

        expect(contact).to have_attributes(name: '+5511888888888')
        expect(contact.additional_attributes).to include('waha_name_source' => 'phone')
      end

      it 'never names the contact after the session business profile on a fromMe message' do
        stub_contact_registry(id: jid, name: nil, pushname: nil)

        contact = resolver(jid: jid, push_name: 'Loja do Zé', from_me: true).perform.contact

        expect(contact.name).to eq('+5511888888888')
      end
    end

    context 'when the contact already exists' do
      it 'upgrades an incomplete contact with the registry name, the phone number and the avatar' do
        contact = create(:contact, account: channel.account, name: '+5511888888888', phone_number: nil)
        create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: jid)
        stub_contact_registry(id: jid, name: 'Maria Silva', pushname: 'mari')
        stub_request(:get, "https://waha.test/api/#{channel.session_name}/chats/#{jid}/picture")
          .to_return(status: 200, body: { url: 'https://waha.test/avatar.jpg' }.to_json, headers: { 'Content-Type' => 'application/json' })
        allow(Avatar::AvatarFromUrlJob).to receive(:perform_later)

        resolver(jid: jid).perform

        expect(contact.reload).to have_attributes(name: 'Maria Silva', phone_number: '+5511888888888')
        expect(contact.additional_attributes).to include('jid' => jid, 'waha_name_source' => 'contact')
        expect(Avatar::AvatarFromUrlJob).to have_received(:perform_later).with(contact, 'https://waha.test/avatar.jpg')
      end

      it 'keeps a name that is already trusted and does not spend a registry lookup on it' do
        contact = create(:contact, account: channel.account, name: 'Maria (cliente VIP)', phone_number: '+5511888888888')
        create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: jid)
        stub_contact_registry(id: jid, name: 'Maria Silva', pushname: 'mari')

        resolver(jid: jid).perform

        expect(contact.reload.name).to eq('Maria (cliente VIP)')
        expect(a_request(:get, "https://waha.test/api/#{channel.session_name}/contacts/#{jid}")).not_to have_been_made
      end
    end

    context 'when the chat is a group' do
      let(:group_jid) { '120363000000000000@g.us' }

      it 'enriches an existing group left with its raw JID as the name' do
        contact = create(:contact, account: channel.account, name: group_jid)
        create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: group_jid)
        stub_request(:get, "https://waha.test/api/#{channel.session_name}/groups/#{group_jid}")
          .to_return(status: 200, body: { Name: 'Família' }.to_json, headers: { 'Content-Type' => 'application/json' })

        resolver(jid: group_jid).perform

        expect(contact.reload.name).to eq('Família')
        expect(channel.contact_aliases).to be_empty
      end
    end
  end

  describe 'LID, phone JID and phone aliases' do
    let(:lid) { '111222333@lid' }
    let(:jid) { '5511888888888@c.us' }

    def payload(id:, chat:, sender_alt: nil)
      fixture = gows_payload('status_reply_text').deep_dup
      fixture['id'] = "false_#{chat}_#{id}"
      fixture['body'] = "message #{id}"
      fixture['from'] = chat
      fixture['_data']['Info']['Chat'] = chat
      fixture['_data']['Info']['SenderAlt'] = sender_alt if sender_alt
      fixture
    end

    it 'keeps the contact, contact inbox and conversation when an unknown LID later resolves to a phone JID' do
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/#{lid}")
        .to_return(status: 200, body: { lid: lid, pn: nil }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 200, body: { lid: lid, pn: jid }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://waha\.test/api/.*/picture}).to_return(status: 404, body: '{}')
      stub_request(:get, %r{https://waha\.test/api/.*/contacts/.*}).to_return(status: 404, body: '{}')

      Waha::IncomingMessageService.new(channel: channel, payload: payload(id: 'LID01', chat: lid)).perform
      original_contact = channel.account.contacts.sole
      original_contact_inbox = channel.inbox.contact_inboxes.sole
      original_conversation = channel.inbox.conversations.sole

      Waha::IncomingMessageService.new(
        channel: channel,
        payload: payload(id: 'LID02', chat: lid, sender_alt: '5511888888888:17@s.whatsapp.net')
      ).perform
      Waha::IncomingMessageService.new(channel: channel, payload: payload(id: 'JID01', chat: jid)).perform

      expect(
        [channel.account.contacts.to_a, channel.inbox.contact_inboxes.to_a, channel.inbox.conversations.to_a]
      ).to eq([[original_contact], [original_contact_inbox], [original_conversation]])
      expect(original_conversation.messages.reload.size).to eq(3)
      expect(original_contact_inbox.reload.source_id).to eq(jid)
      expect(original_contact.reload.phone_number).to eq('+5511888888888')
      expect(channel.contact_aliases.pluck(:alias_type, :value)).to contain_exactly(
        ['lid', lid], ['jid', jid], ['phone', '+5511888888888']
      )
      expect(channel.contact_aliases.distinct.pluck(:contact_inbox_id)).to eq([original_contact_inbox.id])
    end

    it 'does not create person aliases for a group' do
      group_jid = '120363000000000000@g.us'
      stub_request(:get, %r{https://waha\.test/api/.*}).to_return(status: 404, body: '{}')

      contact_inbox = resolver(jid: group_jid).perform

      expect(contact_inbox.source_id).to eq(group_jid)
      expect(channel.contact_aliases).to be_empty
    end

    it 'serializes concurrent resolutions of the same phone identity' do
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 200, body: { lid: nil, pn: jid }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://waha\.test/api/.*}).to_return(status: 404, body: '{}')
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Queue.new
      errors = Queue.new

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            results << resolver(jid: jid).perform.id
          end
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)
      raise errors.pop unless errors.empty?

      expect(Array.new(2) { results.pop }.uniq.one?).to be(true)
      expect(channel.account.contacts.count).to eq(1)
      expect(channel.inbox.contact_inboxes.count).to eq(1)
      expect(channel.contact_aliases.where(alias_type: 'jid', value: jid).count).to eq(1)
    end

    it 'leaves pre-existing duplicate contact inboxes separate and signals the conflict' do
      lid_contact = create(:contact, account: channel.account)
      lid_contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: lid_contact, source_id: lid)
      phone_contact = create(:contact, account: channel.account, phone_number: '+5511888888888')
      phone_contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: phone_contact, source_id: jid)

      result = nil
      signals = capture_waha_signals { result = resolver(jid: lid, sender_alt: '5511888888888@s.whatsapp.net').perform }

      expect(result).to eq(lid_contact_inbox)
      expect(lid_contact_inbox.reload.source_id).to eq(lid)
      expect(phone_contact_inbox.reload.source_id).to eq(jid)
      expect(channel.contact_aliases).to be_empty
      expect(waha_signal(signals, :contact_identity_conflict).first).to include(
        reason: :multiple_claimants, contact_inbox_ids: [lid_contact_inbox.id, phone_contact_inbox.id].sort.join('|')
      )
    end
  end
end
