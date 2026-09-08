require 'rails_helper'

describe Waha::Anchoring do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox) }
  let(:provider_id) { 'false_5511888888888@c.us_AAA111' }

  def mapped_message(id = provider_id)
    create_waha_message(conversation: conversation, inbox: inbox, account: channel.account, source_id: id)
  end

  it 'finds a canonical message without a legacy source_id' do
    message = mapped_message

    expect(message.source_id).to be_nil
    expect(described_class.find_message(channel, provider_id)).to eq(message)
  end

  it 'does not scan legacy messages when no mapping exists' do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: provider_id)

    expect(described_class.find_message(channel, provider_id)).to be_nil
  end

  it 'requires chat context for a bare stanza and isolates channels and chats' do
    message = mapped_message

    expect(described_class.find_message(channel, 'AAA111')).to be_nil
    expect(described_class.find_message(channel, 'AAA111', '5511888888888@c.us')).to eq(message)
    expect(described_class.find_message(channel, 'AAA111', '5511777777777@c.us')).to be_nil
    expect(described_class.find_message(create(:channel_waha), provider_id)).to be_nil
  end

  it 'does not resolve an ambiguous backfill reservation' do
    message = mapped_message
    message.waha_message_mappings.first.update!(ambiguous: true)

    expect(described_class.find_message(channel, provider_id)).to be_nil
    expect(described_class.external_anchor_source_id(message)).to be_nil
  end

  it 'keeps edit families separate when another chat reuses the same stanza' do
    original = mapped_message
    other = mapped_message('false_5511777777777@c.us_AAA111')
    edit = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                               source_id: 'false_5511888888888@c.us_EDIT01', additional_attributes: { 'edit_of' => provider_id })

    expect(described_class.family(inbox, edit)).to contain_exactly(original, edit)
    expect(described_class.family(inbox, other)).to contain_exactly(other)
    expect(described_class.external_anchor_source_id(edit)).to eq(provider_id)
  end
end
