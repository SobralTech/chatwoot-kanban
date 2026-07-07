class CannedResponses::QuickSendService
  # Delay between each step's delivery, so the customer receives them in order
  STEP_DELIVERY_DELAY = 2

  def initialize(user:, conversation:, canned_response:)
    @user = user
    @conversation = conversation
    @canned_response = canned_response
  end

  def perform
    raise StandardError, 'Canned response is not configured for quick send' unless @canned_response.quick_send?

    @canned_response.canned_response_steps.ordered.map.with_index do |step, index|
      Messages::MessageBuilder.new(@user, @conversation, message_params(step, index)).perform
    end
  end

  private

  def message_params(step, index)
    params = {
      content: step.content,
      private: false,
      message_type: 'outgoing',
      send_reply_delay: index * STEP_DELIVERY_DELAY
    }

    params[:attachments] = [step.file_blob_id] if step.media?
    params
  end
end
