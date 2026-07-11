json.payload do
  json.array! @eligible_agents do |agent|
    json.id agent.id
    json.name agent.name
    json.email agent.email
  end
end
