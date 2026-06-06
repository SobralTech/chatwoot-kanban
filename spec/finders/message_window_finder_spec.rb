require 'rails_helper'

RSpec.describe MessageWindowFinder do
  subject(:finder) do
    described_class.new(
      conversation: conversation,
      around: anchor.id,
      before_limit: before_limit,
      after_limit: after_limit
    )
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:before_limit) { nil }
  let(:after_limit) { nil }

  def create_message(minutes_offset, target_conversation: conversation)
    create(
      :message,
      account: target_conversation.account,
      inbox: target_conversation.inbox,
      conversation: target_conversation,
      created_at: Time.zone.parse('2026-01-01 10:00:00') + minutes_offset.minutes
    )
  end

  describe '#perform' do
    let!(:older_messages) { [create_message(1), create_message(2), create_message(3)] }
    let!(:anchor) { create_message(4) }
    let!(:newer_messages) { [create_message(5), create_message(6), create_message(7)] }

    it 'returns messages before anchor, anchor, and messages after anchor' do
      result = finder.perform

      expect(result).to eq(older_messages + [anchor] + newer_messages)
    end

    it 'returns the payload chronologically' do
      result = finder.perform

      expect(result.map(&:created_at)).to eq(result.map(&:created_at).sort)
    end

    context 'with default limits' do
      let!(:older_messages) { Array.new(25) { |index| create_message(index) } }
      let!(:anchor) { create_message(30) }
      let!(:newer_messages) { Array.new(25) { |index| create_message(31 + index) } }

      it 'uses 20 as the default limit' do
        result = finder.perform

        expect(result.length).to eq(41)
        expect(result.first).to eq(older_messages[-20])
        expect(result[20]).to eq(anchor)
        expect(result.last).to eq(newer_messages[19])
      end
    end

    context 'with limits above the maximum' do
      let(:before_limit) { 100 }
      let(:after_limit) { 100 }
      let!(:older_messages) { Array.new(55) { |index| create_message(index) } }
      let!(:anchor) { create_message(60) }
      let!(:newer_messages) { Array.new(55) { |index| create_message(61 + index) } }

      it 'clamps limits to 50' do
        result = finder.perform

        expect(result.length).to eq(101)
        expect(result.first).to eq(older_messages[-50])
        expect(result[50]).to eq(anchor)
        expect(result.last).to eq(newer_messages[49])
      end
    end

    context 'when the anchor belongs to another conversation' do
      let(:other_conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:anchor) { create_message(4, target_conversation: other_conversation) }

      it 'raises not found' do
        expect { finder.perform }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when the anchor is missing' do
      subject(:finder) do
        described_class.new(conversation: conversation, around: -1, before_limit: before_limit, after_limit: after_limit)
      end

      it 'raises not found' do
        expect { finder.perform }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
