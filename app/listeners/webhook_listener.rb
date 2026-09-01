class WebhookListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)

    deliver_webhook_payloads(conversation.inbox, __method__.to_s) do
      conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    end
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)

    deliver_webhook_payloads(conversation.inbox, __method__.to_s) do
      conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    end
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]

    deliver_webhook_payloads(conversation.inbox, __method__.to_s) do
      conversation.webhook_data.merge(event: __method__.to_s)
    end
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    deliver_webhook_payloads(message.inbox, __method__.to_s) do
      message.webhook_data.merge(event: __method__.to_s)
    end
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    deliver_webhook_payloads(message.inbox, __method__.to_s) do
      message.webhook_data.merge(event: __method__.to_s)
    end
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]

    deliver_webhook_payloads(contact_inbox.inbox, __method__.to_s) do
      contact_inbox.webhook_data.merge(event: __method__.to_s, event_info: event.data[:event_info])
    end
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)

    deliver_account_webhooks(account, __method__.to_s) do
      contact.webhook_data.merge(event: __method__.to_s)
    end
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    deliver_account_webhooks(account, __method__.to_s) do
      contact.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    end
  end

  def inbox_created(event)
    inbox, account = extract_inbox_and_account(event)

    deliver_account_webhooks(account, __method__.to_s) do
      Inbox::EventDataPresenter.new(inbox).push_data.merge(event: __method__.to_s)
    end
  end

  def inbox_updated(event)
    inbox, account = extract_inbox_and_account(event)
    changed_attributes = extract_changed_attributes(event)
    return if changed_attributes.blank?

    deliver_account_webhooks(account, __method__.to_s) do
      Inbox::EventDataPresenter.new(inbox).push_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    end
  end

  def conversation_typing_on(event)
    handle_typing_status(__method__.to_s, event)
  end

  def conversation_typing_off(event)
    handle_typing_status(__method__.to_s, event)
  end

  private

  def handle_typing_status(event_name, event)
    conversation = event.data[:conversation]
    user = event.data[:user]

    deliver_webhook_payloads(conversation.inbox, event_name) do
      {
        event: event_name,
        user: user.webhook_data,
        conversation: conversation.webhook_data,
        is_private: event.data[:is_private] || false
      }
    end
  end

  # The payload is built by the block only when something is actually subscribed to the event.
  # Serializing a conversation or message is expensive, and most accounts subscribe to few events.
  def deliver_account_webhooks(account, event_name)
    webhooks = subscribed_account_webhooks(account, event_name)
    return if webhooks.empty?

    dispatch_account_webhooks(webhooks, yield)
  end

  def deliver_webhook_payloads(inbox, event_name)
    webhooks = subscribed_account_webhooks(inbox.account, event_name)
    api_channel = api_inbox_channel(inbox)
    return if webhooks.empty? && api_channel.blank?

    payload = yield
    dispatch_account_webhooks(webhooks, payload)
    dispatch_api_inbox_webhook(api_channel, payload)
  end

  def subscribed_account_webhooks(account, event_name)
    account.webhooks.account_type.select { |webhook| webhook.subscriptions.include?(event_name) }
  end

  def api_inbox_channel(inbox)
    return unless inbox.channel_type == 'Channel::Api'
    return if inbox.channel.webhook_url.blank?

    inbox.channel
  end

  def dispatch_account_webhooks(webhooks, payload)
    webhooks.each do |webhook|
      WebhookJob.perform_later(webhook.url, payload, :account_webhook,
                               secret: webhook.secret,
                               delivery_id: SecureRandom.uuid)
    end
  end

  def dispatch_api_inbox_webhook(channel, payload)
    return if channel.blank?

    WebhookJob.perform_later(channel.webhook_url, payload, :api_inbox_webhook,
                             secret: channel.secret, delivery_id: SecureRandom.uuid)
  end
end
