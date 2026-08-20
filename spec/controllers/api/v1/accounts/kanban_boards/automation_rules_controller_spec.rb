require 'rails_helper'

RSpec.describe 'Kanban automation rules API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:board) { create(:kanban_board, account: account) }
  let(:rule_params) do
    {
      automation_rule: {
        name: 'Notify on card creation',
        description: 'Initial automation',
        event_name: 'card_created',
        conditions: [{ attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'] }],
        actions: [{ action_name: 'set_priority', action_params: { priority: 'high' } }],
        position: 1
      }
    }
  end

  def rules_path
    "/api/v1/accounts/#{account.id}/kanban_boards/#{board.id}/automation_rules"
  end

  it 'creates a disabled dry-run rule for an administrator' do
    expect do
      post rules_path, headers: administrator.create_new_auth_token, params: rule_params, as: :json
    end.to change(KanbanAutomationRule, :count).by(1)

    expect(response).to have_http_status(:success)
    rule = KanbanAutomationRule.last
    expect(rule).not_to be_active
    expect(rule).to be_dry_run
    expect(response.parsed_body['id']).to eq(rule.id)
  end

  it 'lists rules in position order with the execution count placeholder' do
    later_rule = create(:kanban_automation_rule, account: account, kanban_board: board, position: 2)
    first_rule = create(:kanban_automation_rule, account: account, kanban_board: board, position: 1)

    get rules_path, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |rule| rule['id'] }).to eq([first_rule.id, later_rule.id])
    expect(response.parsed_body['payload'].map { |rule| rule['executions_count'] }).to eq([0, 0])
  end

  it 'returns a keyed validation error for an invalid payload' do
    invalid_params = rule_params.deep_dup
    invalid_params[:automation_rule][:event_name] = 'conversation_created'

    post rules_path, headers: administrator.create_new_auth_token, params: invalid_params, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to have_key('event_name')
  end

  it 'toggles the active state' do
    rule = create(:kanban_automation_rule, account: account, kanban_board: board, active: false)

    patch "#{rules_path}/#{rule.id}/toggle", headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(rule.reload).to be_active
  end

  it 'allows the full CRUD lifecycle for an administrator' do
    post rules_path, headers: administrator.create_new_auth_token, params: rule_params, as: :json
    rule = KanbanAutomationRule.last

    patch "#{rules_path}/#{rule.id}",
          headers: administrator.create_new_auth_token,
          params: { automation_rule: { name: 'Updated rule' } },
          as: :json

    expect(response).to have_http_status(:success)
    expect(rule.reload.name).to eq('Updated rule')

    delete "#{rules_path}/#{rule.id}", headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(KanbanAutomationRule.exists?(rule.id)).to be(false)
  end

  it 'returns forbidden to a non-administrator agent' do
    get rules_path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
