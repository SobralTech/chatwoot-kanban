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

    context 'with personal pin_type' do
      it 'rejects a duplicate personal pin for the same conversation and user' do
        existing = create(:conversation_pin, pin_type: :personal)
        duplicate = build(
          :conversation_pin,
          pin_type: :personal,
          conversation: existing.conversation,
          account: existing.account,
          user: existing.user
        )
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:conversation_id]).to be_present
      end

      it 'allows personal pins for the same conversation by different users' do
        existing = create(:conversation_pin, pin_type: :personal)
        other_user = create(:user, account: existing.account, role: :agent)
        pin = build(
          :conversation_pin,
          pin_type: :personal,
          conversation: existing.conversation,
          account: existing.account,
          user: other_user
        )
        expect(pin).to be_valid
      end
    end

    context 'with account pin_type' do
      it 'rejects a duplicate account pin for the same conversation' do
        existing = create(:conversation_pin, pin_type: :account)
        other_user = create(:user, account: existing.account, role: :agent)
        duplicate = build(
          :conversation_pin,
          pin_type: :account,
          conversation: existing.conversation,
          account: existing.account,
          user: other_user
        )
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:conversation_id]).to be_present
      end

      it 'allows multiple conversations pinned at account level' do
        existing = create(:conversation_pin, pin_type: :account)
        other_conv = create(:conversation, account: existing.account)
        other_user = create(:user, account: existing.account, role: :agent)
        pin = build(
          :conversation_pin,
          pin_type: :account,
          conversation: other_conv,
          account: existing.account,
          user: other_user
        )
        expect(pin).to be_valid
      end
    end
  end

  describe 'associations' do
    it 'is destroyed when conversation is destroyed' do
      pin = create(:conversation_pin)
      expect { pin.conversation.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
