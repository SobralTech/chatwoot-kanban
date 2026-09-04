require 'rails_helper'

RSpec.describe Migration::BackfillWahaMessageMappingsJob do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def create_message(source_id:, conversation: self.conversation, message_type: :incoming)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: message_type, source_id: source_id)
  end

  it 'backfills an unambiguous message into the canonical mapping' do
    message = create_message(source_id: 'false_5511888888888@c.us_AAA111')

    stats = described_class.perform_now

    mapping = WahaMessageMapping.find_by!(message: message)
    expect(mapping).to have_attributes(
      channel_waha_id: channel.id, chat_jid: '5511888888888@c.us', external_id: 'AAA111',
      direction: 'incoming', event_type: 'message', part: 0
    )
    expect(stats).to include(checked: 1, backfilled: 1, skipped_ambiguous: 0, skipped_conflict: 0)
  end

  it 'marks an edit mirror with event_type edit' do
    message = create_message(source_id: 'false_5511888888888@c.us_EDIT01')
    message.update!(additional_attributes: { 'edit_of' => 'false_5511888888888@c.us_AAA111' })

    described_class.perform_now

    expect(WahaMessageMapping.find_by!(message: message).event_type).to eq('edit')
  end

  it 'backfills the group participant as participant_jid' do
    group_jid = '120363000000000000@g.us'
    group_contact = create(:contact, account: channel.account, name: 'Family Group')
    group_contact_inbox = create(:contact_inbox, contact: group_contact, inbox: inbox, source_id: group_jid)
    group_conversation = create(:conversation, account: channel.account, inbox: inbox, contact: group_contact,
                                               contact_inbox: group_contact_inbox)
    message = create_message(source_id: 'false_120363000000000000@g.us_GRP001_5511777777777@c.us',
                             conversation: group_conversation)
    message.update!(content_attributes: { 'participant_jid' => '5511777777777@c.us' })

    described_class.perform_now

    mapping = WahaMessageMapping.find_by!(message: message)
    expect(mapping).to have_attributes(chat_jid: group_jid, participant_jid: '5511777777777@c.us')
  end

  it 'reports and skips a message whose conversation has no resolvable chat' do
    # Create the message under a normal conversation first (a live broadcast
    # callback reads conversation.contact_inbox.source_id on create), then null
    # out contact_inbox_id to simulate the edge case the job itself must guard.
    message = create_message(source_id: 'false_unknown@c.us_ZZZ999')
    conversation.update_column(:contact_inbox_id, nil) # rubocop:disable Rails/SkipsModelValidations

    stats = described_class.perform_now

    expect(WahaMessageMapping.where(message: message)).to be_empty
    expect(stats).to include(checked: 1, backfilled: 0, skipped_ambiguous: 1)
  end

  it 'backfills the first of a colliding pair and reports the second as a conflict, without guessing an association' do
    first = create_message(source_id: 'false_5511888888888@c.us_DUP001')
    second = create_message(source_id: 'false_5511888888888@c.us_DUP001_stray')
    # Force the two messages to resolve to the exact same canonical identity —
    # the same bug class the unique index exists to catch.
    allow(Waha::Anchoring).to receive(:stanza_of).and_call_original
    allow(Waha::Anchoring).to receive(:stanza_of).with(second.source_id).and_return('DUP001')

    stats = described_class.perform_now

    expect(WahaMessageMapping.where(chat_jid: '5511888888888@c.us', external_id: 'DUP001').count).to eq(1)
    expect(WahaMessageMapping.find_by(message: first)).to be_present
    expect(WahaMessageMapping.find_by(message: second)).to be_nil
    expect(stats).to include(checked: 2, backfilled: 1, skipped_conflict: 1)
  end

  it 'does not reprocess a message that already has a mapping' do
    message = create_message(source_id: 'false_5511888888888@c.us_AAA111')
    WahaMessageMapping.create!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                               external_id: 'AAA111', direction: :incoming)

    stats = described_class.perform_now

    expect(stats).to include(checked: 0, backfilled: 0)
  end

  it 'scopes to a single channel when channel_id is given' do
    other_channel = create(:channel_waha)
    other_contact = create(:contact, account: other_channel.account)
    other_contact_inbox = create(:contact_inbox, contact: other_contact, inbox: other_channel.inbox, source_id: '5511999999999@c.us')
    other_conversation = create(:conversation, account: other_channel.account, inbox: other_channel.inbox,
                                               contact: other_contact, contact_inbox: other_contact_inbox)
    create(:message, conversation: other_conversation, inbox: other_channel.inbox, account: other_channel.account,
                     message_type: :incoming, source_id: 'false_5511999999999@c.us_OTHER01')
    message = create_message(source_id: 'false_5511888888888@c.us_AAA111')

    stats = described_class.perform_now(channel_id: channel.id)

    expect(WahaMessageMapping.find_by(message: message)).to be_present
    expect(WahaMessageMapping.where(channel: other_channel)).to be_empty
    expect(stats).to include(checked: 1, backfilled: 1)
  end
end
