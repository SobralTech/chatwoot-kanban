json.id note.id
json.content note.content
json.created_at note.created_at.to_i
json.updated_at note.updated_at.to_i

if note.user
  json.user do
    json.id note.user.id
    json.name note.user.name
    json.avatar_url note.user.avatar_url
  end
else
  json.user nil
end

json.attachments note.attachments do |attachment|
  json.id attachment.id
  json.filename attachment.filename.to_s
  json.content_type attachment.content_type
  json.byte_size attachment.byte_size
  json.url url_for(attachment)
end
