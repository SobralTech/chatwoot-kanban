require 'rails_helper'

RSpec.describe WahaMessageMapping do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def build_message(source_id:)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: source_id)
  end

  def build_mapping(**attrs)
    described_class.new({
      channel: channel, message: build_message(source_id: 'false_5511888888888@c.us_AAA111'),
      chat_jid: '5511888888888@c.us', external_id: 'AAA111', direction: :incoming
    }.merge(attrs))
  end

  it 'requires chat_jid and external_id' do
    mapping = build_mapping(chat_jid: nil, external_id: nil)

    expect(mapping).to be_invalid
    expect(mapping.errors[:chat_jid]).to be_present
    expect(mapping.errors[:external_id]).to be_present
  end

  it 'rejects a duplicate identity in the same channel, chat and event type' do
    build_mapping.save!
    duplicate = build_mapping(message: build_message(source_id: 'false_5511888888888@c.us_AAA222'))

    expect(duplicate).to be_invalid
    expect(duplicate.errors[:external_id]).to be_present
  end

  it 'is protected by the database unique index even when the model validation is bypassed' do
    build_mapping.save!
    duplicate = build_mapping(message: build_message(source_id: 'false_5511888888888@c.us_AAA333'))

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows the same external_id in a different chat (a stanza is only unique per chat)' do
    build_mapping.save!
    other_chat = build_mapping(chat_jid: '5511999999999@c.us', message: build_message(source_id: 'false_other@c.us_AAA111'))

    expect(other_chat).to be_valid
  end

  it 'allows the same external_id under a different event_type' do
    build_mapping.save!
    edit = build_mapping(event_type: :edit, message: build_message(source_id: 'false_5511888888888@c.us_EDIT01'))

    expect(edit).to be_valid
  end

  it 'allows a poll vote event to use the poll message as its idempotency anchor' do
    poll = build_mapping
    poll.save!
    vote = build_mapping(event_type: :poll_vote, message: poll.message)

    expect(vote).to be_valid
  end

  describe '.find_mapping' do
    it 'refuses to choose between different messages in candidate chats' do
      build_mapping.save!
      build_mapping(chat_jid: '5511999999999@c.us').save!

      expect do
        described_class.find_mapping(channel: channel, chat_jid: %w[5511888888888@c.us 5511999999999@c.us], external_id: 'AAA111')
      end.to raise_error(CustomExceptions::Waha::AmbiguousIdentity)
    end

    it 'finds an existing mapping by channel, chat_jid, external_id and event_type' do
      mapping = build_mapping.tap(&:save!)

      found = described_class.find_mapping(
        channel: channel, chat_jid: '5511888888888@c.us', external_id: 'AAA111', event_type: :message
      )
      expect(found).to eq(mapping)
    end

    it 'finds mapping when chat_jid is an array of candidates' do
      mapping = build_mapping.tap(&:save!)

      found = described_class.find_mapping(
        channel: channel, chat_jid: ['other@c.us', '5511888888888@c.us'], external_id: 'AAA111'
      )
      expect(found).to eq(mapping)
    end

    it 'returns nil when chat_jid or external_id is blank' do
      expect(described_class.find_mapping(channel: channel, chat_jid: nil, external_id: 'AAA111')).to be_nil
      expect(described_class.find_mapping(channel: channel, chat_jid: '5511888888888@c.us', external_id: nil)).to be_nil
    end
  end

  describe '.create_canonical!' do
    it 'creates a persisted mapping' do
      message = build_message(source_id: 'false_5511888888888@c.us_AAA111')

      mapping = described_class.create_canonical!(
        channel: channel, message: message, chat_jid: '5511888888888@c.us', external_id: 'AAA111', direction: :incoming
      )
      expect(mapping).to be_persisted
      expect(mapping.external_id).to eq('AAA111')
    end

    it 'raises ActiveRecord::RecordInvalid on duplicate identity without swallowing' do
      build_mapping.save!
      other_message = build_message(source_id: 'false_5511888888888@c.us_AAA222')

      expect do
        described_class.create_canonical!(
          channel: channel, message: other_message, chat_jid: '5511888888888@c.us', external_id: 'AAA111', direction: :incoming
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
