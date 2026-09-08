require 'rails_helper'

describe Waha::HistoryMessageWriter do
  let(:media_node_keys) { { 'image' => 'imageMessage', 'video' => 'videoMessage', 'audio' => 'audioMessage' } }
  let(:media_mimetypes) { { 'image' => 'image/jpeg', 'video' => 'video/mp4', 'audio' => 'audio/ogg' } }

  let(:channel) { create(:channel_waha) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: channel.account, name: 'Ana Souza', phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888@c.us') }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    stub_request(:get, /waha\.test/).to_return(status: 404, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  def perform(payload)
    described_class.new(channel: channel, payload: payload, conversation: conversation).perform
    waha_messages(payload['id'], Message.all).first!
  end

  def history_media_payload(fixture, caption: nil)
    payload = gows_payload(fixture).deep_dup
    payload['media'].delete('url')
    payload['body'] = caption
    payload
  end

  def run_history_media_job(message, payload, kind)
    payload['media']['url'] = "http://localhost:3000/api/files/history-#{kind}"
    fetch_path = %r{/chats/5511888888888(?:@|%40)c\.us/messages/.*downloadMedia=true}
    stub_request(:get, fetch_path).to_return(status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "https://waha.test/api/files/history-#{kind}")
      .to_return(status: 200, body: 'bytes', headers: { 'Content-Type' => payload.dig('media', 'mimetype') })

    Waha::HistoryMediaJob.perform_now(channel.id, '5511888888888@c.us', [message.id])
    message.reload
  end

  def history_media_fixture(kind)
    {
      'image' => 'album_item_image_1',
      'video' => 'album_item_video',
      'audio' => 'audio_history'
    }.fetch(kind)
  end

  def expect_history_media_attachment(kind)
    payload = history_media_payload(history_media_fixture(kind))
    message = perform(payload)

    expect_pending_media(message)
    run_history_media_job(message, payload.deep_dup, kind)
    expect_attached_media(message, kind)
  end

  def expect_pending_media(message)
    expect(message.attachments).to be_empty
    expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
    expect(message.content_attributes['media_download_pending']).to be(true)
    expect(message.content_attributes['media_download_provenance']).to eq('waha_history')
    expect(message.content_attributes['media_download_content']).to eq('waha_media_pending')
  end

  def expect_attached_media(message, kind)
    expect(message.attachments.sole.file_type).to eq(kind)
    expect(message.content).to be_nil
    expect(message.content_attributes).not_to have_key('media_download_pending')
    expect(message.content_attributes).not_to have_key('is_unsupported')
  end

  describe 'structured types the payload already carries' do
    it 'attaches a historical location inline, since no later media job would ever fetch it' do
      message = perform(gows_payload('location_static'))

      expect(message.attachments.sole.file_type).to eq('location')
      expect(message.additional_attributes).to include('waha_import_kind' => 'initial', 'imported' => true)
    end

    it 'attaches the original card of a historical shared contact' do
      message = perform(gows_payload('contact_single'))

      expect(message.content).to include('Carlos Lima', '+55 11 3333-2222')
      expect(message.attachments.sole.file.filename.to_s).to eq('contact-1.vcf')
    end

    it 'backdates an event invitation while retaining its converted content' do
      payload = gows_payload('event_creation')
      message = perform(payload)

      expect(message.created_at.to_i).to eq(payload['timestamp'])
      expect(message.content).to include('Reunião de planejamento', 'Sala Aurora')
    end
  end

  describe 'backdated ordering beside live delivery' do
    it 'keeps historical timestamps and ordering without marking the live message imported' do
      historical_time = 2.hours.ago.change(usec: 0)
      historical_payload = gows_payload('status_reply_text').merge(
        'id' => 'false_5511888888888@c.us_HISTORYORDER1',
        'timestamp' => historical_time.to_i,
        'body' => 'historical message'
      )
      live_payload = gows_payload('status_reply_text').merge(
        'id' => 'false_5511888888888@c.us_LIVEORDER1',
        'timestamp' => Time.current.to_i,
        'body' => 'live message'
      )

      historical_message = perform(historical_payload)
      live_message = Waha::IncomingMessageService.new(channel: channel, payload: live_payload).perform

      expect(historical_message.created_at.to_i).to eq(historical_time.to_i)
      expect(live_message.additional_attributes).not_to have_key('imported')
      expect(live_message.created_at).to be > historical_message.created_at
      expect(conversation.messages.reload.order(:created_at).pluck(:id)).to eq(
        [historical_message.id, live_message.id]
      )
      expect(WahaMessageMapping.where(message: conversation.messages).pluck(:external_id)).to contain_exactly(
        'HISTORYORDER1', 'LIVEORDER1'
      )
    end
  end

  describe 'media' do
    it 'leaves the download to Waha::HistoryMediaJob instead of fetching it on the import path' do
      payload = {
        'id' => 'false_5511888888888@c.us_3EB0MEDIA01',
        'timestamp' => 1_757_003_900,
        'from' => '5511888888888@c.us',
        'fromMe' => false,
        'body' => 'olha só',
        'hasMedia' => true,
        'media' => { 'url' => 'https://waha.test/api/files/abc.jpg', 'mimetype' => 'image/jpeg' },
        '_data' => { 'Info' => { 'Chat' => '5511888888888@c.us' }, 'Message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } } }
      }

      message = perform(payload)

      expect(message.attachments).to be_empty
      expect(message.content).to eq('olha só')
    end

    %w[image video audio].each do |kind|
      it "persists a historical #{kind} without a URL as pending media" do
        node_key = media_node_keys.fetch(kind)
        mimetype = media_mimetypes.fetch(kind)
        payload = {
          'id' => "false_5511888888888@c.us_HISTORY_#{kind}",
          'timestamp' => 1_757_003_900,
          'from' => '5511888888888@c.us',
          'fromMe' => false,
          'body' => nil,
          'hasMedia' => true,
          'media' => { 'mimetype' => mimetype },
          '_data' => {
            'Info' => { 'Chat' => '5511888888888@c.us', 'MediaType' => kind },
            'Message' => { node_key => { 'mimetype' => mimetype } }
          }
        }

        message = perform(payload)

        expect(message.attachments).to be_empty
        expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
        expect(message.content_attributes).to include(
          'media_download_pending' => true,
          'media_download_provenance' => 'waha_history',
          'media_download_content' => 'waha_media_pending'
        )
        expect(message.content_attributes).not_to have_key('is_unsupported')
      end
    end

    it 'downloads and attaches historical image media from a GOWS payload' do
      expect_history_media_attachment('image')
    end

    it 'downloads and attaches historical video media from a GOWS payload' do
      expect_history_media_attachment('video')
    end

    it 'downloads and attaches historical audio media from a GOWS payload' do
      expect_history_media_attachment('audio')
    end

    it 'preserves a real caption through historical media attachment' do
      payload = history_media_payload('album_item_image_1', caption: 'legenda histórica')
      message = perform(payload)

      run_history_media_job(message, payload.deep_dup, 'caption')

      expect(message.attachments.sole.file_type).to eq('image')
      expect(message.content).to eq('legenda histórica')
      expect(message.content_attributes).not_to have_key('media_download_pending')
    end

    it 'keeps a historical media caption as content while marking the media pending' do
      payload = {
        'id' => 'false_5511888888888@c.us_HISTORY_caption',
        'timestamp' => 1_757_003_900,
        'from' => '5511888888888@c.us',
        'fromMe' => false,
        'body' => 'legenda histórica',
        'hasMedia' => true,
        'media' => { 'mimetype' => 'image/jpeg' },
        '_data' => {
          'Info' => { 'Chat' => '5511888888888@c.us', 'MediaType' => 'image' },
          'Message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } }
        }
      }

      message = perform(payload)

      expect(message.content).to eq('legenda histórica')
      expect(message.content_attributes).to include('media_download_pending' => true)
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'does not classify a historical caption matching the pending translation as synthetic' do
      payload = {
        'id' => 'false_5511888888888@c.us_HISTORY_translation_caption',
        'timestamp' => 1_757_003_900,
        'from' => '5511888888888@c.us',
        'fromMe' => false,
        'body' => I18n.t('conversations.messages.waha_media_pending'),
        'hasMedia' => true,
        'media' => { 'mimetype' => 'image/jpeg' },
        '_data' => {
          'Info' => { 'Chat' => '5511888888888@c.us', 'MediaType' => 'image' },
          'Message' => { 'imageMessage' => { 'mimetype' => 'image/jpeg' } }
        }
      }

      message = perform(payload)

      expect(message.content).to eq(I18n.t('conversations.messages.waha_media_pending'))
      expect(message.content_attributes['media_download_provenance']).to eq('waha_history')
      expect(message.content_attributes).not_to have_key('media_download_content')
    end
  end
end
