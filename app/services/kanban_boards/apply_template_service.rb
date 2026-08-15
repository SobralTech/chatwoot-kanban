class KanbanBoards::ApplyTemplateService
  def initialize(kanban_board:, template_key: nil)
    @kanban_board = kanban_board
    @template_key = KanbanBoards::TemplateCatalog.key_for(template_key)
    @template = KanbanBoards::TemplateCatalog.fetch(@template_key)
  end

  def perform!
    KanbanBoard.transaction do
      I18n.with_locale(account.locale.presence || I18n.default_locale) do
        regular_stages = create_regular_stages
        won_stage = create_terminal_stage(@template[:won], regular_stages.length + 1, KanbanBoards::TemplateCatalog::WON_COLOR)
        lost_stage = create_terminal_stage(@template[:lost], regular_stages.length + 2, KanbanBoards::TemplateCatalog::LOST_COLOR)

        kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)
        create_lost_reasons
      end
    end

    kanban_board
  end

  private

  attr_reader :kanban_board, :template_key, :template

  delegate :account, to: :kanban_board

  def create_regular_stages
    template[:stages].each_with_index.map do |stage_template, index|
      kanban_board.kanban_stages.create!(
        account: account,
        name: translate_stage_name(stage_template[:name_key]),
        color: stage_template[:color],
        position: index + 1
      )
    end
  end

  def create_terminal_stage(stage_template, position, color)
    kanban_board.kanban_stages.create!(
      account: account,
      name: translate_stage_name(stage_template[:name_key]),
      color: color,
      position: position
    )
  end

  def create_lost_reasons
    template.fetch(:lost_reasons, []).each_with_index do |reason_template, index|
      kanban_board.kanban_reasons.create!(
        account: account,
        title: I18n.t("kanban.board_templates.#{template_key}.reasons.#{reason_template[:title_key]}"),
        reason_type: :lost,
        position: index + 1
      )
    end
  end

  def translate_stage_name(name_key)
    I18n.t("kanban.board_templates.#{template_key}.stages.#{name_key}")
  end
end
