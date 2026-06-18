json.partial! 'api/v1/models/message', message: message
json.conversation do
  json.contact do
    json.name message.conversation.contact.name
    json.thumbnail message.conversation.contact.avatar_url
  end
end
