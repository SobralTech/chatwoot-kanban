require 'rails_helper'

RSpec.describe 'Kanban card timeline API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Qualification') }
  let(:inbox) { create(:inbox, account: account) }
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: stage,
      inbox: inbox
    )
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  it 'records exactly one stage change with source and target names' do
    target_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Proposal')

    expect do
      patch reorder_url(card), headers: agent.create_new_auth_token, params: {
        card: { kanban_stage_id: target_stage.id, position: 1 }
      }, as: :json
    end.to change { card.kanban_card_events.count }.by(1)

    expect(response).to have_http_status(:success)
    event = card.kanban_card_events.last
    expect(event).to have_attributes(event_type: 'stage_changed', user_id: agent.id)
    expect(event.metadata).to include(
      'from_stage_id' => stage.id,
      'to_stage_id' => target_stage.id,
      'from_stage_name' => 'Qualification',
      'to_stage_name' => 'Proposal'
    )
  end

  it 'records lost with the selected reason without a duplicate stage change' do
    won_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Won')
    lost_stage = create(:kanban_stage, account: account, kanban_board: kanban_board, name: 'Lost')
    kanban_board.update!(won_stage_id: won_stage.id, lost_stage_id: lost_stage.id)
    reason = KanbanReason.create!(
      account: account,
      kanban_board: kanban_board,
      title: 'Budget',
      reason_type: :lost
    )

    patch update_url(card),
          headers: agent.create_new_auth_token,
          params: { card: { kanban_stage_id: lost_stage.id, kanban_reason_id: reason.id } },
          as: :json

    expect(response).to have_http_status(:success)
    expect(card.kanban_card_events.pluck(:event_type)).to eq(['lost'])
    expect(card.kanban_card_events.last.metadata).to include(
      'stage_id' => lost_stage.id,
      'reason_id' => reason.id,
      'reason_title' => 'Budget'
    )
  end

  it 'paginates events from newest to oldest' do
    first_event = create(:kanban_card_event, account: account, kanban_card: card, kanban_board: kanban_board, created_at: 2.minutes.ago)
    second_event = create(:kanban_card_event, account: account, kanban_card: card, kanban_board: kanban_board, created_at: 1.minute.ago)

    get events_url(card), headers: agent.create_new_auth_token, params: { limit: 1 }, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |event| event['id'] }).to eq([second_event.id])
    expect(response.parsed_body['has_more']).to be(true)
    expect(response.parsed_body['next_cursor']).to eq(second_event.id)

    get events_url(card), headers: agent.create_new_auth_token,
                          params: { limit: 1, before_id: second_event.id }, as: :json

    expect(response.parsed_body['payload'].map { |event| event['id'] }).to eq([first_event.id])
    expect(response.parsed_body['has_more']).to be(false)
  end

  it 'keeps a card deletion event after removing the card and its previous events' do
    create(:kanban_card_event, account: account, kanban_card: card, kanban_board: kanban_board)
    deleted_card_id = card.id

    delete base_url(card), headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(KanbanCardEvent.where(kanban_card_id: deleted_card_id).pluck(:event_type)).to eq(['card_deleted'])
  end

  it 'returns the latest movement author and timestamp on the card payload' do
    moved_at = 1.hour.ago.change(usec: 0)
    create(
      :kanban_card_event,
      account: account,
      kanban_card: card,
      kanban_board: kanban_board,
      user: agent,
      event_type: 'stage_changed',
      created_at: moved_at
    )

    get base_url(card), headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('moved_by_id' => agent.id, 'moved_at' => moved_at.to_i)
  end

  private

  def base_url(card)
    "/api/v1/accounts/#{account.id}/kanban_boards/#{kanban_board.id}/cards/by_id/#{card.id}"
  end

  def events_url(card)
    "#{base_url(card)}/events"
  end

  def reorder_url(card)
    "#{base_url(card)}/reorder"
  end

  def update_url(card)
    base_url(card)
  end
end
