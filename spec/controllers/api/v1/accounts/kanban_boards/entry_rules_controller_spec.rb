require 'rails_helper'

RSpec.describe 'Kanban board entry rules API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  def rules_url
    "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/entry_rules"
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{board.id}/entry_rules' do
    it 'creates a rule with its inboxes and conditions' do
      post rules_url,
           headers: administrator.create_new_auth_token,
           params: {
             entry_rule: {
               name: 'Vendas urgentes',
               all_inboxes: false,
               inbox_ids: [inbox.id],
               conditions: [{ attribute_key: 'priority', filter_operator: 'is_one_of', values: ['urgent'] }]
             }
           },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('name' => 'Vendas urgentes', 'all_inboxes' => false, 'active' => false)
      expect(response.parsed_body['inbox_ids']).to eq([inbox.id])
      expect(kanban_board.kanban_board_entry_rules.count).to eq(1)
    end

    it 'rejects inboxes from another account' do
      other_inbox = create(:inbox, account: create(:account))

      post rules_url,
           headers: administrator.create_new_auth_token,
           params: { entry_rule: { name: 'Vendas', all_inboxes: false, inbox_ids: [other_inbox.id] } },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(kanban_board.kanban_board_entry_rules).to be_empty
    end

    it 'rejects an unknown condition operator' do
      post rules_url,
           headers: administrator.create_new_auth_token,
           params: {
             entry_rule: {
               name: 'Vendas',
               conditions: [{ attribute_key: 'priority', filter_operator: 'contains', values: ['urgent'] }]
             }
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(kanban_board.kanban_board_entry_rules).to be_empty
    end

    it 'rejects the won stage as a landing stage' do
      won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board)
      kanban_board.update!(won_stage: won_stage)

      post rules_url,
           headers: administrator.create_new_auth_token,
           params: { entry_rule: { name: 'Vendas', kanban_stage_id: won_stage.id } },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects agents' do
      post rules_url,
           headers: agent.create_new_auth_token,
           params: { entry_rule: { name: 'Vendas' } },
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{board.id}/entry_rules/{id}' do
    it 'replaces the inboxes it names' do
      rule = create(:kanban_board_entry_rule, :selected_inboxes, account: account, kanban_board: kanban_board)
      old_inbox = create(:inbox, account: account)
      create(:kanban_board_entry_rule_inbox, account: account, kanban_board_entry_rule: rule, inbox: old_inbox)

      patch "#{rules_url}/#{rule.id}",
            headers: administrator.create_new_auth_token,
            params: { entry_rule: { all_inboxes: false, inbox_ids: [inbox.id, inbox.id] } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['inbox_ids']).to eq([inbox.id])
      expect(rule.reload.inbox_ids).to eq([inbox.id])
    end

    it 'drops the named inboxes when switching to all inboxes' do
      rule = create(:kanban_board_entry_rule, :selected_inboxes, account: account, kanban_board: kanban_board)
      create(:kanban_board_entry_rule_inbox, account: account, kanban_board_entry_rule: rule, inbox: inbox)

      patch "#{rules_url}/#{rule.id}",
            headers: administrator.create_new_auth_token,
            params: { entry_rule: { all_inboxes: true } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(rule.reload.inbox_ids).to be_empty
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{board.id}/entry_rules/reorder' do
    it 'writes the order the ids arrive in' do
      first = create(:kanban_board_entry_rule, account: account, kanban_board: kanban_board, position: 1)
      second = create(:kanban_board_entry_rule, account: account, kanban_board: kanban_board, position: 2)

      patch "#{rules_url}/reorder",
            headers: administrator.create_new_auth_token,
            params: { rule_ids: [second.id, first.id] },
            as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('id')).to eq([second.id, first.id])
    end

    it 'rejects ids from another board' do
      other_rule = create(:kanban_board_entry_rule, account: account)

      patch "#{rules_url}/reorder",
            headers: administrator.create_new_auth_token,
            params: { rule_ids: [other_rule.id] },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/kanban_boards/{board.id}/entry_rules/preview' do
    it 'counts the existing conversations the rule would take in' do
      create(:kanban_stage, account: account, kanban_board: kanban_board)
      create(:conversation, account: account, inbox: inbox, priority: 'urgent')
      create(:conversation, account: account, inbox: inbox)

      post "#{rules_url}/preview",
           headers: administrator.create_new_auth_token,
           params: {
             entry_rule: {
               name: 'Preview',
               all_inboxes: false,
               inbox_ids: [inbox.id],
               conditions: [{ attribute_key: 'priority', filter_operator: 'is_one_of', values: ['urgent'] }]
             }
           },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['count']).to eq(1)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/kanban_boards/{board.id}/entry_rules/{id}/toggle' do
    it 'takes the value it should end up with' do
      rule = create(:kanban_board_entry_rule, account: account, kanban_board: kanban_board, active: false)

      patch "#{rules_url}/#{rule.id}/toggle",
            headers: administrator.create_new_auth_token,
            params: { active: true },
            as: :json

      expect(response).to have_http_status(:success)
      expect(rule.reload).to be_active
    end
  end
end
