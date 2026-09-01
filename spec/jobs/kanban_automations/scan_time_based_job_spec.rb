require 'rails_helper'

RSpec.describe KanbanAutomations::ScanTimeBasedJob do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:card) { create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage) }
  let(:rule) do
    create(
      :kanban_automation_rule,
      account: account,
      kanban_board: board,
      active: true,
      event_name: 'card_stalled',
      threshold_hours: 1
    )
  end

  it 'enqueues a matching card once across repeated scans on the same day' do
    card.update_column(:stage_entered_at, 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    rule
    allow(Redis::Alfred).to receive(:set).and_return(true, false, false)

    expect(KanbanAutomations::RunRulesJob).to receive(:perform_later).once.with(
      card.id,
      [rule.id],
      'card_stalled',
      hash_including('triggered_at' => kind_of(String))
    )

    3.times { described_class.perform_now }
  end

  # The threshold used to live in the conditions as a synthetic `hours_in_stage`
  # filter, so the matcher demanded the card had also been parked in its stage for
  # that long. A card due tomorrow that just moved must still fire.
  it 'enqueues a due_soon card that only just entered its stage' do
    due_rule = create(
      :kanban_automation_rule,
      account: account, kanban_board: board, active: true,
      event_name: 'due_soon', threshold_hours: 24
    )
    card.update!(due_at: 2.hours.from_now, stage_entered_at: 1.minute.ago)
    allow(Redis::Alfred).to receive(:set).and_return(true)

    expect(KanbanAutomations::RunRulesJob).to receive(:perform_later).once.with(
      card.id, [due_rule.id], 'due_soon', anything
    )

    described_class.perform_now
  end

  it 'correlates no-reply message checks to candidate conversations' do
    no_reply_rule = create(
      :kanban_automation_rule,
      account: account, kanban_board: board, active: true,
      event_name: 'no_reply', threshold_hours: 1
    )
    conversation = create(:conversation, account: account)
    no_reply_card = create(
      :kanban_card, :conversation_origin,
      account: account, kanban_board: board, kanban_stage: stage, conversation: conversation
    )
    create(:message, :incoming, account: account, inbox: conversation.inbox, conversation: conversation, created_at: 2.hours.ago)
    allow(Redis::Alfred).to receive(:set).and_return(true)
    sql_queries = []
    callback = ->(_name, _start, _finish, _id, payload) { sql_queries << payload[:sql] if payload[:sql].present? }

    expect(KanbanAutomations::RunRulesJob).to receive(:perform_later).with(
      no_reply_card.id, [no_reply_rule.id], 'no_reply', anything
    )

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { described_class.perform_now }

    candidate_query = sql_queries.find { |sql| sql.include?('EXISTS') && sql.include?('messages') }
    expect(candidate_query).to include('messages.conversation_id = kanban_cards.conversation_id')
  end
end
