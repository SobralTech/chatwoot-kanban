json.access_mode @conversation.access_mode
json.payload do
  json.array! @conversation_access_users do |access_user|
    json.id access_user.user.id
    json.name access_user.user.name
    json.email access_user.user.email
    json.effective_access access_user.effective_access?
  end
end
