class Api::V1::Accounts::ProductsController < Api::V1::Accounts::BaseController
  def search
    result = KanbanProducts::SearchClient.new.search(
      text: params[:text],
      sku: params[:sku],
      price_list: params[:price_list],
      limit: params[:limit]
    )
    render json: result
  rescue KanbanProducts::SearchClient::ApiError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end
