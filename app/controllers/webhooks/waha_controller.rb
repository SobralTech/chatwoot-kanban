class Webhooks::WahaController < ActionController::API
  def process_payload
    channel = Channel::Waha.find_by(webhook_token: params[:token])
    return head :not_found unless channel

    Webhooks::WahaEventsJob.perform_later(channel.id, permitted_params)
    head :ok
  end

  private

  def permitted_params
    params.except(:token, :controller, :action).to_unsafe_hash
  end
end
