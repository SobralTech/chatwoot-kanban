class Api::V1::Accounts::KanbanBoards::Cards::NotesController < Api::V1::Accounts::KanbanBoards::Cards::BaseController
  before_action :fetch_note, only: [:update, :destroy]

  def index
    authorize @kanban_card, :show?

    @notes, @has_more, @next_cursor = cursor_page(@kanban_card.kanban_card_notes.with_attached_attachments.includes(:user).ordered)
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

  def fetch_note
    @note = @kanban_card.kanban_card_notes.find(params[:note_id])
  end

  def note_params
    params.require(:note).permit(:content, attachments: [])
  end
end
