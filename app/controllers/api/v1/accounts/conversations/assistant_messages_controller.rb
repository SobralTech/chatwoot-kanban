class Api::V1::Accounts::Conversations::AssistantMessagesController < Api::V1::Accounts::Conversations::BaseController
  PER_PAGE = 10

  def index
    render json: {
      payload: serialized_assistant_messages,
      meta: { current_page: current_page, total_pages: paginated_assistant_messages.total_pages }
    }
  end

  def create
    assistant_message = ConversationAssistant::AskService.new(
      account: Current.account,
      conversation: @conversation,
      user: Current.user,
      question: create_params[:question]
    ).perform

    if assistant_message.failed?
      render json: serialized_assistant_message(assistant_message), status: :unprocessable_content
    else
      render json: serialized_assistant_message(assistant_message)
    end
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages.to_sentence)
  end

  def send_to_customer
    assistant_message = assistant_messages.find(params[:id])
    message = ConversationAssistant::SendToCustomerService.new(
      assistant_message: assistant_message,
      user: Current.user
    ).perform

    render json: serialized_assistant_message(assistant_message.reload).merge(message: message.push_event_data)
  rescue ConversationAssistant::SendToCustomerService::ValidationError => e
    render_could_not_create_error(e.message)
  rescue StandardError => e
    Rails.logger.error("[ConversationAssistant] send_to_customer failed: #{e.message}")
    render_could_not_create_error(I18n.t('errors.conversation_assistant.send_failed'))
  end

  private

  def assistant_messages
    @conversation.conversation_assistant_messages.where(account: Current.account, user: Current.user)
  end

  def current_page
    (params[:page] || 1).to_i
  end

  def paginated_assistant_messages
    @paginated_assistant_messages ||= assistant_messages.order(created_at: :desc).page(current_page).per(PER_PAGE)
  end

  def serialized_assistant_messages
    paginated_assistant_messages.reverse.map do |assistant_message|
      serialized_assistant_message(assistant_message)
    end
  end

  def serialized_assistant_message(assistant_message)
    {
      id: assistant_message.id,
      question: assistant_message.question,
      suggested_reply: assistant_message.suggested_reply,
      internal_note: assistant_message.internal_note,
      sources: assistant_message.sources,
      model: assistant_message.model,
      web_search_used: assistant_message.web_search_used,
      usage: assistant_message.usage,
      status: assistant_message.status,
      sent_to_customer_at: assistant_message.sent_to_customer_at,
      sent_message_id: assistant_message.sent_message_id,
      created_at: assistant_message.created_at
    }
  end

  def create_params
    params.permit(:question)
  end
end
