class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  # WhatsApp only allows editing a message within 15 minutes of sending it.
  WAHA_EDIT_WINDOW = 15.minutes

  def index
    @messages = message_finder.perform
  end

  def search
    result = conversation_message_search_finder.perform
    @messages = result[:messages]
    @meta = result[:meta]
  rescue ArgumentError => e
    render_could_not_create_error(e.message)
  end

  def window
    @messages = message_window_finder.perform
    @meta = { anchor_id: message_window_params[:around].to_i }
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    Waha::DeleteMessageService.new(message: message).perform if waha_deletable?

    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def waha_edit
    return render_could_not_create_error(I18n.t('conversations.messages.waha_edit_not_allowed')) unless waha_editable?

    Waha::EditMessageService.new(message: message, content: permitted_params[:content]).perform
    head :ok
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def waha_react
    return render_could_not_create_error(I18n.t('conversations.messages.waha_react_not_allowed')) unless waha_reactable?

    Waha::ReactionService.new(message: message, emoji: permitted_params[:emoji].to_s).perform
    head :ok
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  # Only our own messages can be revoked on WhatsApp; deleting a contact's
  # message stays a local-only soft delete.
  def waha_deletable?
    @conversation.inbox.waha? && message.outgoing? && message.source_id.present?
  end

  def waha_editable?
    @conversation.inbox.waha? &&
      message.outgoing? &&
      edit_anchor.present? &&
      edit_anchor.created_at > WAHA_EDIT_WINDOW.ago
  end

  # WhatsApp allows reacting to any message (ours or the contact's), with no
  # time window; only revoked messages, private notes and activities are out.
  def waha_reactable?
    @conversation.inbox.waha? &&
      !message.activity? &&
      !message.private? &&
      message.source_id.present? &&
      !message.content_attributes['deleted']
  end

  # The 15-minute window is measured from the original message, not from the
  # latest edit mirror, so we resolve to the family anchor before checking.
  def edit_anchor
    @edit_anchor ||= begin
      anchor_source_id = message.additional_attributes['edit_of'].presence || message.source_id
      @conversation.messages.find_by(source_id: anchor_source_id)
    end
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def conversation_message_search_finder
    @conversation_message_search_finder ||= ConversationMessageSearchFinder.new(@conversation, params)
  end

  def message_window_finder
    @message_window_finder ||= MessageWindowFinder.new(
      conversation: @conversation,
      around: message_window_params[:around],
      before_limit: message_window_params[:before_limit],
      after_limit: message_window_params[:after_limit]
    )
  end

  def message_window_params
    params.permit(:around, :before_limit, :after_limit)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :content, :emoji)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
