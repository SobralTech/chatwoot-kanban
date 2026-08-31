json.open do
  json.count @summary.open.count
  json.value @summary.open.value
end

json.won_this_month do
  json.count @summary.won_this_month.count
  json.value @summary.won_this_month.value
end

json.lost_this_month do
  json.count @summary.lost_this_month.count
  json.value @summary.lost_this_month.value
end

json.average_ticket @summary.average_ticket
json.new_leads_this_month @summary.new_leads_this_month
json.active_agents_count @summary.active_agents_count
json.leads_with_conversation_count @summary.leads_with_conversation_count
json.origin_summary @summary.origin_summary
json.visible_cards_count @summary.visible_cards_count

json.visible_stages_summary do
  json.array! @summary.visible_stages_summary do |stage|
    json.id stage[:id]
    json.name stage[:name]
    json.cards_count stage[:cards_count]
  end
end

json.stages_summary do
  json.array! @summary.stages_summary do |stage|
    json.id stage[:id]
    json.name stage[:name]
    json.cards_count stage[:cards_count]
  end
end
