class CannedResponses::QuickSendService
  def initialize(user:, conversation:, canned_response:)
    @user = user
    @conversation = conversation
    @canned_response = canned_response
  end

  def perform
    raise StandardError, 'Canned response is not configured for quick send' unless @canned_response.quick_send?

    @canned_response.canned_response_steps.ordered.map do |step|
      Messages::MessageBuilder.new(@user, @conversation, message_params(step)).perform
    end
  end

  private

  def message_params(step)
    params = {
      content: step.content,
      private: false,
      message_type: 'outgoing'
    }

    params[:attachments] = [step.file_blob_id] if step.media?
    params
  end
end
