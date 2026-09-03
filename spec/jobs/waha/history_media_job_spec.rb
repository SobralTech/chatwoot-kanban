require 'rails_helper'

describe Waha::HistoryMediaJob do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox) }

  def build_message(stanza)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     source_id: "false_5511888888888@c.us_#{stanza}")
  end

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  # Media fetches are capped at FETCH_TIMEOUT each, but a chat with hundreds of them
  # would hold one Sidekiq thread for over an hour — and an import enqueues one of
  # these jobs per chat, so a large import could occupy the whole process.
  describe 'thread occupancy' do
    it 'fetches one message per execution and chains the remainder' do
      ids = [build_message('AAA').id, build_message('BBB').id, build_message('CCC').id]

      expect { described_class.perform_now(channel.id, 'chat@c.us', ids) }
        .to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [ids[1], ids[2]], 1)
        .exactly(:once)
    end

    it 'stops the chain on the last message' do
      ids = [build_message('AAA').id]

      expect { described_class.perform_now(channel.id, 'chat@c.us', ids) }
        .not_to have_enqueued_job(described_class)
    end
  end

  describe 'circuit breaker' do
    it 'pauses and resumes the remaining media after reaching the failure limit' do
      ids = [build_message('AAA').id, build_message('BBB').id]

      expect { described_class.perform_now(channel.id, 'chat@c.us', ids, described_class::MAX_CONSECUTIVE_FAILURES - 1) }
        .to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [ids[1]], 0)
        .at(a_value_within(1.second).of(described_class::FAILURE_COOLDOWN.from_now))
    end
  end

  describe 'idempotency' do
    it 'skips a message that already carries an attachment without counting it as a failure' do
      done = build_message('AAA')
      done.attachments.create!(account: channel.account, file_type: :image)
      pending_message = build_message('BBB')

      expect { described_class.perform_now(channel.id, 'chat@c.us', [done.id, pending_message.id], 0) }
        .to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [pending_message.id], 0)
    end
  end
end
