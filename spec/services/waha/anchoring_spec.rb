require 'rails_helper'

describe Waha::Anchoring do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox) }

  def message_with(source_id, **attrs)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: source_id, **attrs)
  end

  # The lookup used to run as `source_id LIKE '%_<stanza>'`, which no index can serve
  # (leading wildcard) — every inbound webhook event scanned the inbox's messages. It
  # now compares the same expression the index is built on, so these pin the matching
  # behaviour across that rewrite.
  describe '.by_stanza' do
    it 'matches a message by the trailing stanza of its source_id' do
      message = message_with('false_5511888888888@c.us_AAA111')

      expect(described_class.by_stanza(inbox, 'AAA111')).to contain_exactly(message)
    end

    it 'matches regardless of the direction and chat the source_id was built from' do
      outgoing = message_with('true_5511777777777@c.us_AAA111')

      expect(described_class.by_stanza(inbox, 'false_5511888888888@c.us_AAA111')).to contain_exactly(outgoing)
    end

    it 'matches a source_id that is a bare stanza' do
      message = message_with('AAA111')

      expect(described_class.by_stanza(inbox, 'AAA111')).to contain_exactly(message)
    end

    it 'does not match a different stanza' do
      message_with('false_5511888888888@c.us_AAA111')

      expect(described_class.by_stanza(inbox, 'BBB222')).to be_empty
    end

    it 'does not match a stanza that is merely a suffix of another' do
      message_with('false_5511888888888@c.us_XAAA111')

      expect(described_class.by_stanza(inbox, 'AAA111')).to be_empty
    end

    it 'is scoped to the inbox' do
      other_inbox = create(:channel_waha, account: channel.account).inbox
      create(:message,
             conversation: create(:conversation, account: channel.account, inbox: other_inbox),
             inbox: other_inbox, account: channel.account, source_id: 'false_5511888888888@c.us_AAA111')

      expect(described_class.by_stanza(inbox, 'AAA111')).to be_empty
    end

    it 'matches nothing when the source_id carries no stanza' do
      expect(described_class.by_stanza(inbox, nil)).to be_empty
    end
  end
end
