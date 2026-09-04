class Waha::DeliverJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    Waha::SendOnWahaService.new(message: message, skip_presence: true).perform
  end
end
