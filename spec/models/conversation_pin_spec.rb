require 'rails_helper'

RSpec.describe ConversationPin do
  describe 'validations' do
    it 'is valid with all required attributes' do
      expect(build(:conversation_pin)).to be_valid
    end

    it 'requires pinned_at' do
      pin = build(:conversation_pin, pinned_at: nil)
      expect(pin).not_to be_valid
      expect(pin.errors[:pinned_at]).to be_present
    end

    it 'requires account' do
      pin = build(:conversation_pin)
      pin.account = nil
      expect(pin).not_to be_valid
    end

    it 'requires conversation' do
      pin = build(:conversation_pin)
      pin.conversation = nil
      expect(pin).not_to be_valid
    end

    it 'requires user' do
      pin = build(:conversation_pin)
      pin.user = nil
      expect(pin).not_to be_valid
    end

    it 'rejects a duplicate pin for the same conversation' do
      existing = create(:conversation_pin)
      other_user = create(:user, account: existing.account, role: :agent)
      duplicate = build(
        :conversation_pin,
        conversation: existing.conversation,
        account: existing.account,
        user: other_user
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end

    it 'allows multiple conversations to be pinned' do
      existing = create(:conversation_pin)
      other_conv = create(:conversation, account: existing.account)
      other_user = create(:user, account: existing.account, role: :agent)
      pin = build(
        :conversation_pin,
        conversation: other_conv,
        account: existing.account,
        user: other_user
      )
      expect(pin).to be_valid
    end
  end

  describe 'associations' do
    it 'is destroyed when conversation is destroyed' do
      pin = create(:conversation_pin)
      expect { pin.conversation.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
