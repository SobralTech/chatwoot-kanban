require 'rails_helper'

describe Waha::SendOnWahaService do
  self.use_transactional_tests = false

  around do |example|
    clean_database!
    example.run
  ensure
    clean_database!
  end

  let(:channel) { create(:channel_waha, typing_simulation_enabled: false, auto_read_receipts: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def clean_database!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.disable_referential_integrity do
        (connection.tables - %w[schema_migrations ar_internal_metadata]).each do |table|
          connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
        end
      end
    end
  end

  before do
    stub_request(:get, %r{https://waha\.test/api/.+/new-message-id})
      .to_return(status: 200, body: { id: 'RACEID01' }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, 'https://waha.test/api/sendText')
      .to_return(status: 201, body: { id: 'true_5511888888888@c.us_RACEID01' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe 'two concurrent delivery attempts for the same message' do
    it 'makes at most one active sendText call and converges on a single confirmed mapping' do
      message = create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
                                    message_type: :outgoing, content: 'hello')

      barrier = Concurrent::CyclicBarrier.new(2)
      errors = Concurrent::Array.new

      threads = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            msg = Message.find(message.id)
            barrier.wait
            described_class.new(message: msg, skip_presence: true).perform
          end
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)

      expect(errors).to be_empty
      expect(a_request(:post, 'https://waha.test/api/sendText')).to have_been_made.once
      expect(WahaMessageMapping.where(message: message).count).to eq(1)
      expect(message.reload.presented_source_id).to eq('true_5511888888888@c.us_RACEID01')
      expect(WahaDeliveryAttempt.find_by(message: message)).to have_attributes(status: 'sent', attempt_count: 1)
    end
  end
end
