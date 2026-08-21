require 'rails_helper'

RSpec.describe KanbanBoards::SummaryQuery do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:kanban_board) { create(:kanban_board, account: account) }
  let!(:regular_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, position: 1) }
  let!(:won_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, position: 2) }
  let!(:lost_stage) { create(:kanban_stage, account: account, kanban_board: kanban_board, position: 3) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    kanban_board.update!(won_stage: won_stage, lost_stage: lost_stage)
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe '#call' do
    it 'excludes cards in inboxes the agent cannot access' do
      create_card(stage: regular_stage, inbox: inbox)
      create_card(stage: regular_stage, inbox: create(:inbox, account: account))

      result = query.call

      expect(result.open).to have_attributes(count: 1, value: BigDecimal('10.0'))
      expect(result.won_this_month.count).to eq(0)
    end

    it 'applies assignee filters to every metric' do
      other_agent = create(:user, account: account, role: :agent)
      administrator = create(:user, account: account, role: :administrator)
      administrator_account_user = administrator.account_users.find_by!(account: account)
      create_card(stage: regular_stage, inbox: inbox, assignees: [agent])
      create_card(stage: regular_stage, inbox: inbox, assignees: [other_agent])

      result = query(
        user: administrator,
        account_user: administrator_account_user,
        filtered_assignee_ids: [other_agent.id]
      ).call

      expect(result.open).to have_attributes(count: 1, value: BigDecimal('10.0'))
    end

    it 'keeps won and lost cards out of the open metric' do
      create_card(stage: regular_stage, inbox: inbox)
      create_card(stage: won_stage, inbox: inbox)
      create_card(stage: lost_stage, inbox: inbox)

      result = query.call

      expect(result.open).to have_attributes(count: 1, value: BigDecimal('10.0'))
    end

    it 'counts only the lost cards that entered the stage this month' do
      travel_to(Time.utc(2026, 3, 15, 12)) do
        create_card(stage: lost_stage, inbox: inbox, stage_entered_at: Time.utc(2026, 3, 2))
        create_card(stage: lost_stage, inbox: inbox, stage_entered_at: Time.utc(2026, 2, 27))

        result = query.call

        expect(result.lost_this_month).to have_attributes(count: 1, value: BigDecimal('10.0'))
      end
    end

    it 'counts every card as open when the board has no won and lost stages' do
      kanban_board.update!(won_stage: nil, lost_stage: nil)
      create_card(stage: regular_stage, inbox: inbox)
      create_card(stage: won_stage, inbox: inbox)

      result = query.call

      expect(result.open).to have_attributes(count: 2, value: BigDecimal('20.0'))
      expect(result.won_this_month).to have_attributes(count: 0, value: BigDecimal('0.0'))
      expect(result.lost_this_month).to have_attributes(count: 0, value: BigDecimal('0.0'))
      expect(result.average_ticket).to be_nil
    end

    it 'uses the account timezone for the current month boundary' do
      account.update!(reporting_timezone: 'America/Sao_Paulo')

      travel_to(Time.utc(2026, 3, 15, 12)) do
        create_card(
          stage: won_stage,
          inbox: inbox,
          stage_entered_at: Time.utc(2026, 3, 1, 2, 30)
        )
        create_card(
          stage: won_stage,
          inbox: inbox,
          stage_entered_at: Time.utc(2026, 3, 1, 3, 30)
        )

        result = query.call

        expect(result.won_this_month).to have_attributes(count: 1, value: BigDecimal('10.0'))
        expect(result.average_ticket).to eq('10.00')
      end
    end
  end

  def query(**options)
    described_class.new(
      account: account,
      kanban_board: kanban_board,
      visible_cards: KanbanCards::VisibleCardsScope.new(
        account: account,
        user: options.fetch(:user, agent),
        kanban_board: kanban_board,
        account_user: options[:account_user],
        filtered_assignee_ids: options[:filtered_assignee_ids]
      ).call
    )
  end

  def create_card(stage:, inbox:, assignees: [], stage_entered_at: Time.current)
    card = create(
      :kanban_card,
      account: account,
      kanban_board: kanban_board,
      kanban_stage: stage,
      inbox: inbox,
      contact: create(:contact, account: account)
    )
    card.update!(stage_entered_at: stage_entered_at)
    card.update_assignees!(assignees.map(&:id)) if assignees.present?
    create_product(card)
    card
  end

  def create_product(card)
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
