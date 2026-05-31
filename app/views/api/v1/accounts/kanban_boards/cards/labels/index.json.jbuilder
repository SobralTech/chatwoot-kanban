json.payload @labels do |label|
  json.extract! label, :id, :title, :color, :description
end
