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

  it 'quarantines every claimant of a colliding identity without choosing a message' do
    first = create_message(source_id: 'false_5511888888888@c.us_DUP001')
    second = create_message(source_id: 'true_5511888888888@c.us_DUP001')

    stats = described_class.perform_now

    expect(WahaMessageMapping.where(chat_jid: '5511888888888@c.us', external_id: 'DUP001').count).to eq(1)
    expect(WahaMessageMapping.find_by(message: first)).to be_present
    expect(WahaMessageMapping.find_by(message: second)).to be_nil
    expect(Waha::Anchoring.find_message(channel, first.source_id)).to be_nil
    expect(Waha::Anchoring.find_message(channel, second.source_id)).to be_nil
    expect(WahaMessageMapping.find_by(message: first)).to be_ambiguous
    expect(stats).to include(checked: 2, backfilled: 1, skipped_conflict: 2)
  end

  it 'fills provider metadata without creating a second mapping on repeated runs' do
    message = create_message(source_id: 'false_5511888888888@c.us_AAA111')
    WahaMessageMapping.create!(channel: channel, message: message, chat_jid: '5511888888888@c.us',
                               external_id: 'AAA111', direction: :incoming)

    stats = described_class.perform_now

    expect(stats).to include(checked: 1, backfilled: 0)
    expect(WahaMessageMapping.find_by!(message: message).provider_id).to eq(message.source_id)
    expect { described_class.perform_now }.not_to change(WahaMessageMapping, :count)
  end

  it 'keeps old replies and edit families usable after the legacy columns are cleared' do
    original = create_message(source_id: 'false_5511888888888@c.us_OLD01')
    edit = create_message(source_id: 'false_5511888888888@c.us_EDIT01')
    edit.update!(additional_attributes: { 'edit_of' => original.source_id })
    described_class.perform_now
    [original, edit].each { |message| message.update!(source_id: nil, additional_attributes: {}) }

    result = Waha::ReplyContextResolver.new(channel: channel, conversation: conversation,
                                            payload: { 'replyTo' => { 'id' => 'OLD01' } }).perform

    expect(result).to include(in_reply_to: edit.id, in_reply_to_external_id: 'false_5511888888888@c.us_OLD01')
    expect(Waha::Anchoring.family(inbox, edit)).to contain_exactly(original, edit)
  end

  it 'reports a disagreement between the provider chat and conversation without mapping it' do
    message = create_message(source_id: 'false_5511777777777@c.us_WRONG01')

    expect(described_class.perform_now).to include(skipped_ambiguous: 1)
    expect(message.waha_message_mappings).to be_empty
  end

  it 'converts a dispatched pre-multipart attempt so its returning echo confirms the same message' do
    message = create_message(source_id: nil, message_type: :outgoing)
    attempt = WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id,
                                          status: :sending, client_message_id: 'PENDING01', dispatched_at: Time.current)
    described_class.perform_now

    payload = { 'id' => 'true_5511888888888@c.us_PENDING01', 'fromMe' => true, 'to' => contact_inbox.source_id }
    Webhooks::WahaEventsJob.perform_now(channel.id, { 'session' => channel.session_name, 'event' => 'message.any', 'payload' => payload })

    expect(attempt.reload).to be_sent
    expect(inbox.messages).to contain_exactly(message)
    expect(message.reload.source_id).to be_nil
    expect(message.presented_source_id).to eq('true_5511888888888@c.us_PENDING01')
  end

  it 'preserves every previously confirmed multipart provider ID' do
    message = create_message(source_id: 'true_5511888888888@c.us_FIRST', message_type: :outgoing)
    attempt = WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id, status: :sent)
    %w[FIRST SECOND].each_with_index do |stanza, position|
      attempt.delivery_parts.create!(position: position, part_type: :text, status: :sent,
                                     external_id: stanza, source_id: "true_5511888888888@c.us_#{stanza}")
      WahaMessageMapping.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id,
                                 direction: :outgoing, external_id: stanza, part: position)
    end

    described_class.perform_now

    expect(Waha::Anchoring.mappings_for(message).pluck(:provider_id))
      .to eq(%w[true_5511888888888@c.us_FIRST true_5511888888888@c.us_SECOND])
  end

  it 'recovers a confirmed legacy attempt even when its old message correlation is missing' do
    message = create_message(source_id: nil, message_type: :outgoing)
    WahaDeliveryAttempt.create!(channel: channel, message: message, chat_jid: contact_inbox.source_id, status: :sent, external_id: 'CONFIRMED')
    edit = create_message(source_id: 'true_5511888888888@c.us_EDITRECOVERED', message_type: :outgoing)
    edit.update!(additional_attributes: { 'edit_of' => 'true_5511888888888@c.us_CONFIRMED' })

    described_class.perform_now

    expect(Waha::Anchoring.find_message(channel, 'true_5511888888888@c.us_CONFIRMED')).to eq(message)
    expect(message.reload.source_id).to be_nil
    expect(Waha::Anchoring.family_anchor_message(edit)).to eq(message)
  end

  it 'retains old revoked identities for deduplication without age-based expiry' do
    message = create_message(source_id: 'false_5511888888888@c.us_OLD01')
    message.update!(created_at: 5.years.ago, content_attributes: { 'deleted' => true })

    described_class.perform_now

    expect(Waha::Anchoring.find_message(channel, message.source_id)).to eq(message)
    expect(Waha::Anchoring.external_anchor_source_id(message)).to eq(message.source_id)
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
