class Api::V1::Accounts::KanbanBoards::Cards::ProductsController < Api::V1::Accounts::KanbanBoards::Cards::BaseController
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
    authorize @kanban_card, :update?
    return render_catalog_price_forbidden if catalog_price_update_by_non_admin?

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

  def fetch_kanban_card_product
    @kanban_card_product = @kanban_card.kanban_card_products.find(params[:product_id])
  end

  def product_params
    params.permit(:sku, :name, :brand, :image_url, :quantity, :unit_price, :price_type, :price_list, :item_type)
  end

  def update_product_params
    params.permit(:unit_price, :quantity)
  end

  # Catalog prices come from the price list, so only an administrator may override
  # one. Manually added service and custom lines are priced on the card itself and
  # stay editable by anyone who can edit the card.
  def catalog_price_update_by_non_admin?
    @kanban_card_product.catalog? && !Current.account_user&.administrator? && params.key?(:unit_price)
  end

  def product_metadata(product)
    {
      sku: product.sku,
      name: product.name,
      item_type: product.item_type,
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

  def render_catalog_price_forbidden
    render json: { error: 'Only administrators can change the price of a catalog product' }, status: :forbidden
  end
end
