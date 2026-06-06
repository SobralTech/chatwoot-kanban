json.meta do
  json.anchor_id @meta[:anchor_id]
end

json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/message', message: message
  end
end
