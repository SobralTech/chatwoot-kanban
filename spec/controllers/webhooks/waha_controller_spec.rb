require 'rails_helper'

RSpec.describe 'Webhooks::WahaController', type: :request do
  let(:channel) { create(:channel_waha) }

  def post_waha_webhook(payload)
    post "/webhooks/waha/#{channel.webhook_token}", params: payload, as: :json
  end

  it 'enqueues an event only when the payload session belongs to the channel' do
    allow(Webhooks::WahaEventsJob).to receive(:perform_later)

    post_waha_webhook(session: channel.session_name, event: 'message.any', payload: { id: 'message-id' })

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WahaEventsJob).to have_received(:perform_later).with(
      channel.id,
      hash_including('session' => channel.session_name, 'event' => 'message.any')
    )
  end

  it 'rejects an event whose session belongs to a different channel' do
    allow(Webhooks::WahaEventsJob).to receive(:perform_later)

    post_waha_webhook(session: 'another_session', event: 'message.any', payload: { id: 'message-id' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('errors.messages.waha_webhook_session_mismatch'))
    expect(Webhooks::WahaEventsJob).not_to have_received(:perform_later)
  end

  it 'rejects a webhook without a session' do
    allow(Webhooks::WahaEventsJob).to receive(:perform_later)

    post_waha_webhook(event: 'message.any', payload: { id: 'message-id' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('errors.messages.waha_webhook_session_mismatch'))
    expect(Webhooks::WahaEventsJob).not_to have_received(:perform_later)
  end

  it 'reports a pre-existing connection conflict without processing the webhook' do
    # Simulates the non-destructive flag written by the migration for legacy duplicates.
    # rubocop:disable Rails/SkipsModelValidations
    channel.update_column(:connection_identity_conflict, true)
    # rubocop:enable Rails/SkipsModelValidations
    allow(Webhooks::WahaEventsJob).to receive(:perform_later)

    post_waha_webhook(session: channel.session_name, event: 'message.any', payload: { id: 'message-id' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('errors.messages.waha_connection_conflict'))
    expect(Webhooks::WahaEventsJob).not_to have_received(:perform_later)
  end
end
