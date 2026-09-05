require 'rails_helper'

describe Waha::InboundEventPolicy do
  describe '.message' do
    it 'represents direct and group chats' do
      expect(described_class.message('5511888888888@c.us')).to have_attributes(action: :represent, reason: :direct_or_group_chat)
      expect(described_class.message('120363000000000000@g.us')).to have_attributes(action: :represent, reason: :direct_or_group_chat)
    end

    it 'has distinct explicit ignore policies for status, newsletters, and broadcasts' do
      expect(described_class.message('status@broadcast')).to have_attributes(action: :ignore, reason: :status_broadcast_chat)
      expect(described_class.message('120363000000000000@newsletter')).to have_attributes(action: :ignore, reason: :newsletter_chat)
      expect(described_class.message('120363000000000000@broadcast')).to have_attributes(action: :ignore, reason: :broadcast_chat)
      expect(described_class.message('120363000000000000@g.us', groups_enabled: false))
        .to have_attributes(action: :ignore, reason: :groups_disabled)
    end
  end

  describe '.call' do
    it 'represents a complete direct GOWS call event' do
      expect(described_class.call('id' => 'CALL01', 'from' => '5511888888888@c.us', 'isGroup' => false))
        .to have_attributes(action: :represent, reason: :direct_call)
    end

    it 'explicitly ignores group and incomplete calls' do
      expect(described_class.call('id' => 'CALL02', 'from' => '120363000000000000@g.us', 'isGroup' => true))
        .to have_attributes(action: :ignore, reason: :group_call)
      expect(described_class.call('from' => '5511888888888@c.us', 'isGroup' => false))
        .to have_attributes(action: :ignore, reason: :missing_call_id)
      expect(described_class.call('id' => 'CALL03', 'isGroup' => false))
        .to have_attributes(action: :ignore, reason: :missing_call_participant)
    end
  end
end
