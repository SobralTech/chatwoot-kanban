require 'rails_helper'

RSpec.describe WahaContactAlias do
  let(:channel) { create(:channel_waha) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox) }

  it 'enforces one owner for an alias in a channel at the database level' do
    described_class.create!(channel: channel, contact_inbox: contact_inbox, alias_type: 'lid', value: '111222333@lid')
    duplicate = described_class.new(
      channel: channel,
      contact_inbox: create(:contact_inbox, inbox: channel.inbox),
      alias_type: 'lid',
      value: '111222333@lid'
    )

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'scopes the same alias to its WAHA channel' do
    described_class.create!(channel: channel, contact_inbox: contact_inbox, alias_type: 'jid', value: '5511888888888@c.us')
    other_channel = create(:channel_waha, account: channel.account)

    alias_record = described_class.new(
      channel: other_channel,
      contact_inbox: create(:contact_inbox, inbox: other_channel.inbox),
      alias_type: 'jid',
      value: '5511888888888@c.us'
    )

    expect(alias_record).to be_valid
  end

  it 'normalizes phone aliases before enforcing uniqueness' do
    described_class.create!(channel: channel, contact_inbox: contact_inbox, alias_type: 'phone', value: '55 (11) 88888-8888')

    duplicate = described_class.new(
      channel: channel,
      contact_inbox: create(:contact_inbox, inbox: channel.inbox),
      alias_type: 'phone',
      value: '+5511888888888'
    )

    expect(duplicate).to be_invalid
    expect(channel.contact_aliases.reload.sole.value).to eq('+5511888888888')
  end
end
