json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: @kanban_board

json.stages do
  json.array! @kanban_stages do |kanban_stage|
    json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: kanban_stage

    stage_states = @conversation_kanban_states&.select { |state| state.kanban_stage_id == kanban_stage.id }
    stage_cards = @kanban_cards&.select { |card| card.kanban_stage_id == kanban_stage.id }
    json.cards do
      if stage_cards
        json.array! stage_cards do |card|
          json.partial!(
            'api/v1/accounts/kanban_boards/card',
            formats: [:json],
            card: card,
            conversation_kanban_state: @conversation_kanban_states_by_conversation_id[card.conversation_id]
          )
        end
      else
        json.array! stage_states do |conversation_kanban_state|
          json.partial!(
            'api/v1/accounts/kanban_boards/card',
            formats: [:json],
            conversation_kanban_state: conversation_kanban_state
          )
        end
      end
    end
  end
end
