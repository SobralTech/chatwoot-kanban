require 'rails_helper'

describe Waha::HistoryMediaJob do
  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: channel.account, inbox: inbox) }

  def build_message(stanza)
    create_waha_message(conversation: conversation, inbox: inbox, account: channel.account,
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
      done.update!(
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true, 'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending', 'is_unsupported' => true
        }
      )
      pending_message = build_message('BBB')

      expect { described_class.perform_now(channel.id, 'chat@c.us', [done.id, pending_message.id], 0) }
        .to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [pending_message.id], 0)

      expect(done.reload.content).to be_nil
      expect(done.content_attributes).not_to have_key('media_download_pending')
      expect(done.content_attributes).not_to have_key('is_unsupported')
    end
  end

  describe 'transient failures' do
    it 'keeps the item at the front of the queue for a retry, without dropping it' do
      message = build_message('AAA')
      message.update!(
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true,
          'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending'
        }
      )
      stub_request(:get, /waha\.test/).to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { described_class.perform_now(channel.id, 'chat@c.us', [message.id]) }
        .to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [message.id], 1)

      expect(message.reload.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be_nil
      expect(message.content_attributes['media_download_pending']).to be(true)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
    end

    it 'attaches the media once the transient failure clears, without a duplicate attachment' do
      message = build_message('AAA')
      message.update!(
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true, 'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending', 'is_unsupported' => true
        }
      )
      fetch_path = %r{/chats/5511888888888(?:@|%40)c\.us/messages/}
      payload = {
        'id' => message.presented_source_id, 'hasMedia' => true, 'type' => 'image',
        'media' => { 'url' => 'http://localhost:3000/api/files/abc.jpeg', 'mimetype' => 'image/jpeg' }
      }
      # WebMock replays the responses of a single stub in sequence per matching
      # request, so the first job execution sees the 503 and the second (after
      # the item stayed queued) sees the successful fetch.
      stub_request(:get, fetch_path)
        .to_return({ status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' } },
                   { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } })
      stub_request(:get, 'https://waha.test/api/files/abc.jpeg')
        .to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })

      described_class.perform_now(channel.id, 'chat@c.us', [message.id])
      expect(message.reload.attachments).to be_empty

      expect { described_class.perform_now(channel.id, 'chat@c.us', [message.id], 1) }
        .not_to have_enqueued_job(described_class)

      expect(message.reload.attachments.size).to eq(1)
      expect(message.content).to be_nil
      expect(message.content_attributes).not_to have_key('media_download_pending')
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end
  end

  describe 'terminal failures' do
    it 'registers a visible fallback and advances past the item instead of dropping it silently' do
      message = build_message('AAA')
      message.update!(
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true, 'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending', 'is_unsupported' => true
        }
      )
      # The default before-block stub (404) is a permanent, non-retryable miss.

      expect { described_class.perform_now(channel.id, 'chat@c.us', [message.id]) }
        .not_to have_enqueued_job(described_class)

      message.reload
      expect(message.attachments).to be_empty
      expect(message.content_attributes['media_download_failed']).to be(true)
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
      expect(message.content_attributes).not_to have_key('media_download_pending')
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'reconciles a terminal synthetic placeholder if a later execution finds the media' do
      message = build_message('RECOVER')
      message.update!(
        content: I18n.t('conversations.messages.waha_media_pending'),
        content_attributes: {
          'media_download_pending' => true, 'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending'
        }
      )

      expect { described_class.perform_now(channel.id, 'chat@c.us', [message.id]) }
        .not_to have_enqueued_job(described_class)

      message.reload
      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_unavailable'))
      expect(message.content_attributes['media_download_provenance']).to eq('waha_history')

      payload = {
        'id' => message.presented_source_id, 'hasMedia' => true, 'type' => 'image',
        'media' => { 'url' => 'http://localhost:3000/api/files/recovered.jpeg', 'mimetype' => 'image/jpeg' }
      }
      fetch_path = %r{/chats/5511888888888(?:@|%40)c\.us/messages/}
      stub_request(:get, fetch_path).to_return(status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'https://waha.test/api/files/recovered.jpeg')
        .to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => 'image/jpeg' })

      described_class.perform_now(channel.id, 'chat@c.us', [message.id])

      message.reload
      expect(message.attachments.size).to eq(1)
      expect(message.content).to be_nil
      expect(message.content_attributes.keys).not_to include(
        'media_download_failed', 'media_download_provenance', 'media_download_content'
      )
    end
  end

  describe 'circuit breaker resuming a transient failure' do
    it 'retries the item that tripped the breaker instead of skipping past it' do
      stuck = build_message('AAA')
      next_message = build_message('BBB')
      stub_request(:get, /waha\.test/).to_return(status: 503, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect do
        described_class.perform_now(channel.id, 'chat@c.us', [stuck.id, next_message.id], described_class::MAX_CONSECUTIVE_FAILURES - 1)
      end.to have_enqueued_job(described_class)
        .with(channel.id, 'chat@c.us', [stuck.id, next_message.id], 0)
        .at(a_value_within(1.second).of(described_class::FAILURE_COOLDOWN.from_now))
    end
  end
end
