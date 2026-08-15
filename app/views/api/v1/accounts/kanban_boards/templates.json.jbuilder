json.array! @templates do |template|
  json.key template[:key]
  json.name template[:name]
  json.description template[:description]
  json.stages template[:stages]
  json.won_stage_name template[:won_stage_name]
  json.lost_stage_name template[:lost_stage_name]
  json.lost_reasons_count template[:lost_reasons_count]
  json.custom_fields_count template[:custom_fields_count]
end
