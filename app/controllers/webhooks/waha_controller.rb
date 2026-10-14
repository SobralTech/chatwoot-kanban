class Webhooks::WahaController < ActionController::API
  def process_payload
    channel = Channel::Waha.find_by(webhook_token: params[:token])
    return head :not_found unless channel

    error = channel.webhook_error(params[:session])
    return ignore_event(channel, error) if error

    Webhooks::WahaEventsJob.perform_later(channel.id, permitted_params)
    head :ok
  end

  private

  # WAHA retries every non-2xx delivery (15 attempts by default), so a rejected
  # event answers 200 with the reason instead of triggering a retry storm.
  def ignore_event(channel, error)
    reason = channel.connection_identity_conflict? ? :connection_identity_conflict : :session_mismatch
    Waha::Telemetry.emit(:event_ignored, channel: channel, level: :warn, event: params[:event], reason: reason)
    render json: { error: error }, status: :ok
  end

  def permitted_params
    params.except(:token, :controller, :action).to_unsafe_hash
  end
end
