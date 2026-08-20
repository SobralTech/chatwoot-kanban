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
