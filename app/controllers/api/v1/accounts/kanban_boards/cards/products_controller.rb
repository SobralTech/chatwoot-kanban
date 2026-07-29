class Api::V1::Accounts::KanbanBoards::Cards::ProductsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_board
  before_action :fetch_kanban_card
  before_action :fetch_kanban_card_product, only: [:update, :destroy]

  def index
    authorize @kanban_card, :show?
    @kanban_card_products = @kanban_card.kanban_card_products.ordered
  end

  def create
    authorize @kanban_card, :update?
    @kanban_card_product = @kanban_card.kanban_card_products.create!(
      product_params.merge(account: Current.account)
    )
  end

  def update
    return render_forbidden unless Current.account_user&.administrator?

    @kanban_card_product.update!(update_product_params)
  end

  def destroy
    authorize @kanban_card, :update?
    @kanban_card_product.destroy!
    head :no_content
  end

  private

  def fetch_kanban_board
    @kanban_board = policy_scope(KanbanBoard).find(params[:kanban_board_id])
  end

  def fetch_kanban_card
    @kanban_card = @kanban_board.kanban_cards.active.joins(:kanban_stage).merge(KanbanStage.active).find(params[:id])
  end

  def fetch_kanban_card_product
    @kanban_card_product = @kanban_card.kanban_card_products.find(params[:product_id])
  end

  def product_params
    params.permit(:sku, :name, :brand, :image_url, :quantity, :unit_price, :price_type, :price_list)
  end

  def update_product_params
    params.permit(:unit_price, :quantity)
  end

  def render_forbidden
    render json: { error: 'Only administrators can edit a linked product' }, status: :forbidden
  end
end
