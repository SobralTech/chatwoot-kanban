json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: @kanban_board

json.stages do
  json.array! @kanban_stages do |kanban_stage|
    json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: kanban_stage

    stage_states = @conversation_kanban_states.select { |state| state.kanban_stage_id == kanban_stage.id }
    json.cards do
      json.array! stage_states do |conversation_kanban_state|
        json.partial! 'api/v1/accounts/kanban_boards/card', formats: [:json],
                      conversation_kanban_state: conversation_kanban_state
      end
    end
  end
end
