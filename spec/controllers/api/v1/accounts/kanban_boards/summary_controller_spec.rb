require 'rails_helper'

RSpec.describe 'Kanban board summary API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:regular_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 1) }
  let!(:won_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 2) }
  let!(:lost_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 3) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    board.update!(won_stage: won_stage, lost_stage: lost_stage)
  end

  it 'returns the filtered funnel metrics' do
    create_card(regular_stage)
    create_card(won_stage)
    create_card(lost_stage)

    get summary_url, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include(
      'open' => { 'count' => 1, 'value' => '10.0' },
      'won_this_month' => { 'count' => 1, 'value' => '10.0' },
      'lost_this_month' => { 'count' => 1, 'value' => '10.0' },
      'average_ticket' => '10.00',
      'currency' => 'BRL'
    )
  end

  def summary_url
    "/api/v1/accounts/#{account.id}/kanban_boards/#{board.id}/summary"
  end

  def create_card(stage)
    card = create(
      :kanban_card,
      account: account,
      kanban_board: board,
      kanban_stage: stage,
      inbox: inbox,
      contact: create(:contact, account: account)
    )
    KanbanCardProduct.create!(
      account: account,
      kanban_card: card,
      sku: SecureRandom.hex(4),
      name: 'Product',
      unit_price: 10,
      quantity: 1
    )
  end
end
