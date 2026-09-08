require 'rails_helper'

describe Waha::CallEventService do
  let(:channel) { create(:channel_waha) }
  let(:contact) { create(:contact, account: channel.account, name: 'John Doe', phone_number: '+5511888888888') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5511888888888@c.us') }

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def payload(overrides = {})
    {
      'id' => 'CALL01',
      'from' => '5511888888888@c.us',
      'timestamp' => 1_762_358_460,
      'isVideo' => false,
      'isGroup' => false,
      '_data' => { 'Data' => { 'Attrs' => {} } }
    }.merge(overrides)
  end

  it 'represents the received direct call as an activity with its observable GOWS data' do
    message = described_class.new(channel: channel, event: 'call.received', payload: payload('duration' => 42)).perform

    expect(message).to have_attributes(message_type: 'activity', conversation: contact_inbox.conversations.last)
    expect(message.content).to eq('WhatsApp incoming voice call received (42s)')
    expect(message.content_attributes['waha_call']).to eq(
      'id' => 'CALL01',
      'direction' => 'incoming',
      'participant_jid' => '5511888888888@c.us',
      'result' => 'received',
      'is_video' => false,
      'duration' => 42,
      'event' => 'call.received'
    )
    expect(WahaMessageMapping.find_by!(message: message)).to have_attributes(
      chat_jid: '5511888888888@c.us', external_id: 'CALL01:call.received', event_type: 'call', direction: 'incoming'
    )
  end

  %w[call.accepted call.rejected].each do |event|
    it "represents the #{event} lifecycle result without implementing a call" do
      message = described_class.new(channel: channel, event: event, payload: payload('id' => event)).perform

      expect(message.message_type).to eq('activity')
      expect(message.content_attributes.dig('waha_call', 'result')).to eq(event.delete_prefix('call.'))
      expect(message.content_attributes.dig('waha_call', 'is_video')).to be(false)
    end
  end

  it 'is idempotent when GOWS redelivers a call event' do
    service = described_class.new(channel: channel, event: 'call.received', payload: payload)

    expect { 2.times { service.perform } }.to change(Message, :count).by(1)
  end

  it 'ignores an unsupported group call with an operational signal' do
    group_payload = payload('id' => 'GROUPCALL01', 'from' => '120363000000000000@g.us', 'isGroup' => true)

    signals = capture_waha_signals do
      expect { described_class.new(channel: channel, event: 'call.received', payload: group_payload).perform }.not_to change(Message, :count)
    end

    expect(waha_signal(signals, :event_ignored).first).to include(event: 'call.received', reason: :group_call)
  end
end
