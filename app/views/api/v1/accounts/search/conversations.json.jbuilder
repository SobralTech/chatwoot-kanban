json.payload do
  json.conversations do
    json.array! @result[:conversations] do |conversation|
      json.partial! 'conversation_search_result', formats: [:json], conversation: conversation
    end
  end
end
