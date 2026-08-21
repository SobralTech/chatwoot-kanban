require 'rails_helper'

RSpec.describe KanbanAutomations::GuardrailService do
  let(:account) { create(:account, reporting_timezone: 'UTC') }
  let(:board) { create(:kanban_board, account: account, automation_settings: board_settings) }
  let(:stage) { create(:kanban_stage, account: account, kanban_board: board) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account, timezone: 'UTC') }
  let(:conversation) do
    create(:conversation, account: account, contact: contact, inbox: inbox)
  end
  let(:card) do
    create(
      :kanban_card,
      account: account,
      kanban_board: board,
      kanban_stage: stage,
      contact: contact,
      inbox: inbox,
      conversation: conversation,
      origin: 'conversation'
    )
  end
  let(:rule) { create(:kanban_automation_rule, account: account, kanban_board: board, active: true, dry_run: false) }
  let(:context) { { triggered_at: 10.minutes.ago.iso8601 } }
  let(:action_params) { { content: 'Hello' } }

  before do
    allow(GlobalConfigService).to receive(:load).with('KANBAN_AUTOMATIONS_ENABLED', 'true').and_return('true')
  end

  describe '.check' do
    it 'blocks messages outside the configured business hours' do
      board.update!(automation_settings: board_settings.merge(business_hours: { start: '08:00', end: '18:00', days: [1, 2, 3, 4, 5, 6] }))

      travel_to Time.zone.parse('2026-08-24 19:00:00') do
        expect_check_to_be_blocked('outside_business_hours')
      end
    end

    it 'blocks after the contact limit is reached' do
      2.times do
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'outgoing',
          private: false,
          sender: create(:user, account: account),
          content_attributes: { automation_rule_id: rule.id },
          created_at: 1.hour.ago
        )
      end

      expect_check_to_be_blocked('max_auto_messages_per_contact')
    end

    it 'blocks when a human agent spoke recently' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: 'outgoing',
        private: false,
        sender: create(:user, account: account),
        content: 'A human reply',
        created_at: 5.minutes.ago
      )

      expect_check_to_be_blocked('human_silence')
    end

    it 'blocks when the customer replied after the trigger' do
      trigger_time = 10.minutes.ago
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: 'incoming',
        private: false,
        sender: contact,
        content: 'I replied',
        created_at: 5.minutes.ago
      )

      expect_check_to_be_blocked('customer_replied', context: { triggered_at: trigger_time.iso8601 })
    end

    it 'blocks resolved conversations unless the rule allows them' do
      conversation.update!(status: :resolved)

      expect_check_to_be_blocked('conversation_resolved')
      expect(described_class.check(card: card, rule: rule, action_params: action_params.merge(allow_resolved: true), context: context))
        .to be_allowed
    end

    it 'always blocks cards without a conversation' do
      card_without_conversation = create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox
      )

      result = described_class.check(card: card_without_conversation, rule: rule, action_params: action_params, context: context)

      expect(result).not_to be_allowed
      expect(result.reason).to eq('card_without_conversation')
    end
  end

  def board_settings
    {
      business_hours: { start: '00:00', end: '23:59', days: [0, 1, 2, 3, 4, 5, 6] },
      max_auto_messages_per_contact_per_day: 2,
      human_silence_minutes: 30,
      enabled: true
    }
  end

  def expect_check_to_be_blocked(reason, context: self.context)
    result = described_class.check(card: card, rule: rule, action_params: action_params, context: context)

    expect(result).not_to be_allowed
    expect(result.reason).to eq(reason)
  end
end
