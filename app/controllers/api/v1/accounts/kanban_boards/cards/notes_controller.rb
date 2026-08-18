class Api::V1::Accounts::KanbanBoards::Cards::NotesController < Api::V1::Accounts::BaseController
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  before_action :fetch_kanban_board
  before_action :fetch_kanban_card
  before_action :fetch_note, only: [:update, :destroy]

  def index
    authorize @kanban_card, :show?

    notes = paginated_notes.limit(limit + 1).to_a
    @has_more = notes.length > limit
    @notes = notes.first(limit)
    @next_cursor = @has_more ? @notes.last.id : nil
  end

  def create
    authorize @kanban_card, :show?

    @note = @kanban_card.kanban_card_notes.new(note_params)
    @note.account = Current.account
    @note.user = Current.user
    @note.save!

    render :create, status: :created
  end

  def update
    authorize @kanban_card, :show?
    authorize @note, :update?

    @note.update!(note_params)

    render :update
  end

  def destroy
    authorize @kanban_card, :show?
    authorize @note, :destroy?

    @note.destroy!
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def fetch_note
    @note = @kanban_card.kanban_card_notes.find(params[:note_id])
  end

  def paginated_notes
    notes = @kanban_card.kanban_card_notes.with_attached_attachments.includes(:user).ordered
    return notes if params[:before_id].blank?

    cursor = @kanban_card.kanban_card_notes.find(params[:before_id])
    notes.where('(kanban_card_notes.created_at, kanban_card_notes.id) < (?, ?)', cursor.created_at, cursor.id)
  end

  def note_params
    params.require(:note).permit(:content, attachments: [])
  end

  def limit
    (params[:limit] || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
  end
end
