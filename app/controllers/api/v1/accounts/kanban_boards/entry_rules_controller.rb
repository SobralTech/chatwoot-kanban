class Api::V1::Accounts::KanbanBoards::EntryRulesController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :authorize_kanban_board
  before_action :fetch_entry_rule, only: [:update, :destroy, :toggle]

  def index
    @entry_rules = scoped_rules.ordered
  end

  def create
    @entry_rule = KanbanBoardEntryRule.new(
      rule_attributes.merge(
        account: Current.account,
        kanban_board: @kanban_board,
        position: next_position
      )
    )

    save_with_inboxes or return render_validation_error
    render :show
  end

  def update
    @entry_rule.assign_attributes(rule_attributes)

    save_with_inboxes or return render_validation_error
    render :show
  end

  def destroy
    @entry_rule.destroy!
    head :no_content
  end

  # Takes the value it should end up with, so a retry or a double click is a no-op rather
  # than a flip back.
  def toggle
    active = params.key?(:active) ? ActiveModel::Type::Boolean.new.cast(params[:active]) : !@entry_rule.active?
    @entry_rule.update!(active: active)
    render :show
  end

  def reorder
    ordered_ids = Array(params[:rule_ids]).map(&:to_i)
    return render_unknown_rules if scoped_rules.where(id: ordered_ids).count != ordered_ids.size

    scoped_rules.apply_position_order!(ordered_ids)
    @entry_rules = scoped_rules.ordered
    render :index
  end

  # How many existing conversations this rule would take in. The dialog shown when a rule
  # is created, or widened, asks for this before offering the retroactive import.
  def preview
    rule = KanbanBoardEntryRule.new(
      rule_attributes.merge(account: Current.account, kanban_board: @kanban_board, position: 1)
    )
    return render json: { error: rule.errors.messages }, status: :unprocessable_content unless rule.valid?

    render json: { count: import_service(preview_rule_with_inboxes(rule)).estimated_count }
  end

  private

  def scoped_rules
    KanbanBoardEntryRule.where(account_id: Current.account.id, kanban_board_id: @kanban_board.id)
  end

  def fetch_kanban_board
    @kanban_board = KanbanBoard.where(account_id: Current.account.id).find(params[:kanban_board_id])
  end

  def fetch_entry_rule
    @entry_rule = scoped_rules.find(params[:id])
  end

  def authorize_kanban_board
    authorize @kanban_board, :update?
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to do this action' }, status: :forbidden
  end

  def entry_rule_params
    params.require(:entry_rule).permit(
      :name, :active, :all_inboxes, :kanban_stage_id,
      inbox_ids: [],
      conditions: [:attribute_key, :filter_operator, { values: [] }]
    )
  end

  def rule_attributes
    entry_rule_params.except(:inbox_ids)
  end

  def next_position
    (scoped_rules.maximum(:position) || 0) + 1
  end

  # The join table mirrors the rule's inbox side, so it is rewritten with the rule inside
  # one transaction: a rule that saved but kept its old inboxes would narrow the board to
  # something nobody asked for.
  def save_with_inboxes
    saved = false
    KanbanBoardEntryRule.transaction do
      raise ActiveRecord::Rollback unless @entry_rule.save

      replace_inboxes!
      saved = true
    end
    saved
  end

  def replace_inboxes!
    return unless entry_rule_params.key?(:inbox_ids) || @entry_rule.all_inboxes?

    @entry_rule.kanban_board_entry_rule_inboxes.delete_all
    return if @entry_rule.all_inboxes?

    validated_inbox_ids.each do |inbox_id|
      KanbanBoardEntryRuleInbox.create!(
        account: Current.account, kanban_board: @kanban_board,
        kanban_board_entry_rule: @entry_rule, inbox_id: inbox_id
      )
    end
  end

  def validated_inbox_ids
    inbox_ids = Array(entry_rule_params[:inbox_ids]).filter_map(&:presence).map(&:to_i).uniq
    return inbox_ids if Inbox.where(account_id: Current.account.id, id: inbox_ids).count == inbox_ids.length

    raise ActiveRecord::RecordInvalid, @entry_rule
  end

  # The preview runs against a rule that was never saved, so its inboxes are attached in
  # memory for the import service to read.
  def preview_rule_with_inboxes(rule)
    inbox_ids = Array(entry_rule_params[:inbox_ids]).filter_map(&:presence).map(&:to_i).uniq
    rule.define_singleton_method(:inbox_ids) { inbox_ids }
    rule
  end

  def import_service(rule)
    KanbanCards::ImportExistingConversationsService.new(
      account: Current.account, kanban_board: @kanban_board, entry_rule: rule
    )
  end

  def render_unknown_rules
    render json: { error: { rule_ids: ['must all belong to this board'] } }, status: :unprocessable_content
  end

  def render_validation_error
    render json: { error: @entry_rule.errors.messages }, status: :unprocessable_content
  end
end
