json.meta do
  json.total_count @meta[:total_count]
  json.limit @meta[:limit]
  json.has_more @meta[:has_more]
  json.next_before_id @meta[:next_before_id]
end

json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/message', message: message
  end
end
