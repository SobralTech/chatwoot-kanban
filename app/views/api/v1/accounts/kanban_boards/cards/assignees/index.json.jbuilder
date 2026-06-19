json.payload @assignees do |assignee|
  json.extract! assignee, :id, :name
  json.avatar_url assignee.avatar_url
end
json.assignable_users @assignable_users do |user|
  json.extract! user, :id, :name
  json.avatar_url user.avatar_url
end
