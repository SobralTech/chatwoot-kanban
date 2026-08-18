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
    KanbanCard.transaction do
      @kanban_card_product = @kanban_card.kanban_card_products.create!(
        product_params.merge(account: Current.account)
      )
      record_product_event('product_added', product_metadata(@kanban_card_product))
    end
  end

  def update
    return render_forbidden unless Current.account_user&.administrator?

    previous_unit_price = @kanban_card_product.unit_price
    previous_quantity = @kanban_card_product.quantity

    KanbanCard.transaction do
      @kanban_card_product.update!(update_product_params)
      if previous_unit_price != @kanban_card_product.unit_price
        record_product_event(
          'product_price_changed',
          { sku: @kanban_card_product.sku, name: @kanban_card_product.name, from: previous_unit_price, to: @kanban_card_product.unit_price }
        )
      end
      if previous_quantity != @kanban_card_product.quantity
        record_product_event(
          'product_quantity_changed',
          { sku: @kanban_card_product.sku, name: @kanban_card_product.name, from: previous_quantity, to: @kanban_card_product.quantity }
        )
      end
    end
  end

  def destroy
    authorize @kanban_card, :update?
    KanbanCard.transaction do
      metadata = product_metadata(@kanban_card_product)
      @kanban_card_product.destroy!
      record_product_event('product_removed', metadata)
    end
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

  def product_metadata(product)
    {
      sku: product.sku,
      name: product.name,
      quantity: product.quantity,
      unit_price: product.unit_price
    }
  end

  def record_product_event(event_type, metadata)
    KanbanCards::RecordEventService.call(
      card: @kanban_card,
      event_type: event_type,
      user: Current.user,
      metadata: metadata
    )
  end

  def render_forbidden
    render json: { error: 'Only administrators can edit a linked product' }, status: :forbidden
  end
end
