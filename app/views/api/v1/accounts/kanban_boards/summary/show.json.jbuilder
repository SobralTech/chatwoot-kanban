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

json.stages_summary do
  json.array! @summary.stages_summary do |stage|
    json.id stage[:id]
    json.cards_count stage[:cards_count]
  end
end
