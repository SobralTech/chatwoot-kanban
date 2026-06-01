json.partial! 'api/v1/accounts/kanban_boards/kanban_board', formats: [:json], kanban_board: @kanban_board

json.stages do
  json.array! @kanban_stages do |kanban_stage|
    json.partial! 'api/v1/accounts/kanban_boards/stage', formats: [:json], kanban_stage: kanban_stage

    stage_cards = @kanban_cards.select { |card| card.kanban_stage_id == kanban_stage.id }
    json.cards do
      json.array! stage_cards do |card|
        json.partial!(
          'api/v1/accounts/kanban_boards/compact_card',
          formats: [:json],
          card: card
        )
      end
    end
  end
end
