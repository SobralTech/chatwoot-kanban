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

  def preview_path
    "#{rules_path}/preview"
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

  it 'previews the active cards matching an unsaved rule' do
    stage = create(:kanban_stage, account: account, kanban_board: board)
    create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, priority: :high)
    create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, priority: :low)

    post preview_path,
         headers: administrator.create_new_auth_token,
         params: {
           automation_rule: {
             event_name: 'card_created',
             conditions: [{ attribute_key: 'priority', filter_operator: 'equal_to', values: ['high'] }],
             actions: []
           }
         },
         as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('count' => 1, 'limit' => 500, 'capped' => false)
  end

  it 'applies an explicit active state so a repeated toggle is a no-op' do
    rule = create(:kanban_automation_rule, account: account, kanban_board: board, active: false)

    2.times do
      patch "#{rules_path}/#{rule.id}/toggle",
            headers: administrator.create_new_auth_token,
            params: { active: true },
            as: :json
    end

    expect(rule.reload).to be_active
  end

  it 'reorders every rule in one request' do
    first, second, third = Array.new(3) do |index|
      create(:kanban_automation_rule, account: account, kanban_board: board, position: index + 1)
    end

    patch "#{rules_path}/reorder",
          headers: administrator.create_new_auth_token,
          params: { rule_ids: [third.id, first.id, second.id] },
          as: :json

    expect(response).to have_http_status(:success)
    expect([third, first, second].map { |rule| rule.reload.position }).to eq([1, 2, 3])
  end

  it 'rejects a reorder naming a rule from another board' do
    other_rule = create(:kanban_automation_rule, account: account)
    rule = create(:kanban_automation_rule, account: account, kanban_board: board, position: 1)

    patch "#{rules_path}/reorder",
          headers: administrator.create_new_auth_token,
          params: { rule_ids: [other_rule.id, rule.id] },
          as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(rule.reload.position).to eq(1)
  end
end
