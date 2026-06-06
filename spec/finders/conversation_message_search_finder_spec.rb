require 'rails_helper'

RSpec.describe ConversationMessageSearchFinder do
  subject(:finder) { described_class.new(conversation, params) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:params) { { q: query } }
  let(:query) { 'needle' }

  describe '#perform' do
    it 'orders results by id desc' do
      first_message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'needle first')
      second_message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'needle second')

      result = finder.perform

      expect(result[:messages].pluck(:id)).to eq([second_message.id, first_message.id])
    end

    it 'uses 20 as the default limit' do
      create_list(:message, 21, account: account, inbox: inbox, conversation: conversation, content: 'needle')

      result = finder.perform

      meta = result[:meta]

      expect(result[:messages].length).to eq(20)
      expect(meta[:limit]).to eq(20)
      expect(meta[:has_more]).to be(true)
      expect(meta[:next_before_id]).to eq(result[:messages].last.id)
    end

    it 'clamps limit to 50' do
      create_list(:message, 55, account: account, inbox: inbox, conversation: conversation, content: 'needle')

      result = described_class.new(conversation, { q: query, limit: 100 }).perform

      expect(result[:messages].length).to eq(50)
      expect(result[:meta][:limit]).to eq(50)
      expect(result[:meta][:has_more]).to be(true)
    end

    it 'uses before_id as the next page cursor' do
      messages = create_list(:message, 3, account: account, inbox: inbox, conversation: conversation, content: 'needle')

      result = described_class.new(conversation, { q: query, limit: 1, before_id: messages.last.id }).perform

      meta = result[:meta]

      expect(result[:messages].pluck(:id)).to eq([messages.second.id])
      expect(meta[:has_more]).to be(true)
      expect(meta[:next_before_id]).to eq(messages.second.id)
    end

    it 'returns the total matching count independent of cursor pagination' do
      messages = create_list(:message, 3, account: account, inbox: inbox, conversation: conversation, content: 'needle')

      result = described_class.new(conversation, { q: query, limit: 1, before_id: messages.last.id }).perform

      meta = result[:meta]

      expect(meta[:total_count]).to eq(3)
    end

    it 'strips the search query' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'needle found')

      result = described_class.new(conversation, { q: '  needle  ' }).perform

      expect(result[:messages]).to contain_exactly(message)
    end

    it 'raises an error for a blank query' do
      expect { described_class.new(conversation, { q: ' ' }).perform }.to raise_error(ArgumentError, 'Search query is required')
    end
  end
end
