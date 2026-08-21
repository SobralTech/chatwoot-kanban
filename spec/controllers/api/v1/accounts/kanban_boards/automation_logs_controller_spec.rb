require 'rails_helper'

RSpec.describe 'Kanban automation logs API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:log) do
    create(
      :kanban_automation_log,
      account: account,
      kanban_automation_rule: create(:kanban_automation_rule, account: account, kanban_board: board),
      event_name: 'card_created',
      status: 'simulated',
      details: { actions: [{ action_name: 'send_message', status: 'executed' }] }
    )
  end

  def logs_path
    "/api/v1/accounts/#{account.id}/kanban_boards/#{board.id}/automation_logs"
  end

  it 'lists logs for an administrator' do
    get logs_path, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].first).to include(
      'id' => log.id,
      'status' => 'simulated',
      'event_name' => 'card_created'
    )
  end

  it 'filters logs by status' do
    create(:kanban_automation_log, account: account, kanban_automation_rule: log.kanban_automation_rule, status: 'failed')

    get logs_path, params: { status: 'failed' }, headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].map { |item| item['status'] }).to eq(['failed'])
  end

  it 'returns forbidden to a non-administrator agent' do
    get logs_path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
