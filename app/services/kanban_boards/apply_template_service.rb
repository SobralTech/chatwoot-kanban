class KanbanBoards::ApplyTemplateService
  def initialize(kanban_board:, template_key: nil)
    @kanban_board = kanban_board
    @template_key = KanbanBoards::TemplateCatalog.key_for(template_key)
    @template = KanbanBoards::TemplateCatalog.fetch(@template_key)
  end

  def perform!
    KanbanBoard.transaction do
      I18n.with_locale(account.locale.presence || I18n.default_locale) do
        create_stages!
        create_reasons!
        create_custom_fields!
      end
    end

    kanban_board
  end

  private

  attr_reader :kanban_board, :template_key, :template

  delegate :account, to: :kanban_board

  def create_stages!
    regular_stages = template[:stages].each_with_index.map do |stage_template, index|
      create_stage(stage_template[:name_key], stage_template[:color], index + 1)
    end

    kanban_board.update!(
      won_stage: create_stage(template[:won][:name_key], KanbanBoards::TemplateCatalog::WON_COLOR, regular_stages.length + 1),
      lost_stage: create_stage(template[:lost][:name_key], KanbanBoards::TemplateCatalog::LOST_COLOR, regular_stages.length + 2)
    )
  end

  def create_reasons!
    template.fetch(:lost_reasons, []).each_with_index do |reason_key, index|
      kanban_board.kanban_reasons.create!(
        account: account,
        title: I18n.t("kanban.board_templates.#{template_key}.lost_reasons.#{reason_key}"),
        reason_type: :lost,
        position: index + 1
      )
    end
  end

  def create_custom_fields!
    template.fetch(:custom_fields, []).each_with_index do |field_template, index|
      kanban_board.kanban_custom_fields.create!(
        account: account,
        key: I18n.t("kanban.board_templates.#{template_key}.custom_fields.#{field_template[:key]}"),
        field_type: field_template[:field_type],
        position: index + 1
      )
    end
  end

  def create_stage(name_key, color, position)
    kanban_board.kanban_stages.create!(
      account: account,
      name: I18n.t("kanban.board_templates.#{template_key}.stages.#{name_key}"),
      color: color,
      position: position
    )
  end
end
