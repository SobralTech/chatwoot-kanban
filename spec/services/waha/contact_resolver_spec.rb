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

  describe 'LID, phone JID and phone aliases' do
    let(:lid) { '111222333@lid' }
    let(:jid) { '5511888888888@c.us' }

    def payload(id:, chat:, sender_alt: nil)
      {
        'id' => "false_#{chat}_#{id}",
        'body' => "message #{id}",
        'from' => chat,
        'to' => '5511999999999@c.us',
        'fromMe' => false,
        'type' => 'chat',
        'hasMedia' => false,
        '_data' => {
          'Info' => { 'Chat' => chat, 'PushName' => 'Jane Doe', 'SenderAlt' => sender_alt }.compact
        }
      }
    end

    it 'keeps the contact, contact inbox and conversation when an unknown LID later resolves to a phone JID' do
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/#{lid}")
        .to_return(status: 200, body: { lid: lid, pn: nil }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, "https://waha.test/api/#{channel.session_name}/lids/pn/#{jid}")
        .to_return(status: 200, body: { lid: lid, pn: jid }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://waha\.test/api/.*/picture}).to_return(status: 404, body: '{}')

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

    it 'leaves pre-existing duplicate contact inboxes separate and logs the conflict' do
      lid_contact = create(:contact, account: channel.account)
      lid_contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: lid_contact, source_id: lid)
      phone_contact = create(:contact, account: channel.account, phone_number: '+5511888888888')
      phone_contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: phone_contact, source_id: jid)
      allow(Rails.logger).to receive(:error)

      result = resolver(jid: lid, sender_alt: '5511888888888@s.whatsapp.net').perform

      expect(result).to eq(lid_contact_inbox)
      expect(lid_contact_inbox.reload.source_id).to eq(lid)
      expect(phone_contact_inbox.reload.source_id).to eq(jid)
      expect(channel.contact_aliases).to be_empty
      expect(Rails.logger).to have_received(:error).with(
        /contact alias conflict.*contact_inbox_ids=#{lid_contact_inbox.id},#{phone_contact_inbox.id}/
      )
    end
  end
end
