json.payload @events do |event|
  json.id event.id
  json.event_type event.event_type
  json.metadata event.metadata
  json.created_at event.created_at.to_i
  if event.user
    json.user do
      json.id event.user.id
      json.name event.user.name
      json.avatar_url event.user.avatar_url
    end
  else
    json.user nil
  end
end
json.has_more @has_more
json.next_cursor @next_cursor
