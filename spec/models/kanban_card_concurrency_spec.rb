require 'rails_helper'

RSpec.describe KanbanCard, type: :model do
  self.use_transactional_tests = false

  around do |example|
    clean_database!
    example.run
  ensure
    clean_database!
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:board) { create(:kanban_board, account: account, auto_create_cards_from_conversations: true) }
  let(:first_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 1) }
  let(:second_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 2) }
  let(:third_stage) { create(:kanban_stage, account: account, kanban_board: board, position: 3) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:thread_timeout) { 10.seconds }
  let(:statement_timeout_ms) { 5_000 }
  let(:lock_timeout_ms) { 2_000 }

  before do
    create(:inbox_member, user: user, inbox: inbox)
  end

  it 'keeps active positions stable after two simultaneous same-stage reorders' do
    cards = create_cards(first_stage, 5)
    create_inactive_card(first_stage)

    errors = run_concurrently(
      -> { described_class.find(cards.first.id).reorder_to_position!(kanban_stage: KanbanStage.find(first_stage.id), position: 5) },
      -> { described_class.find(cards.last.id).reorder_to_position!(kanban_stage: KanbanStage.find(first_stage.id), position: 1) }
    )

    expect(errors).to be_empty
    expect_card_invariants
  end

  it 'keeps active positions stable after simultaneous cross-stage moves involving the same stages' do
    first_stage_cards = create_cards(first_stage, 4)
    second_stage_cards = create_cards(second_stage, 4)
    create_inactive_card(first_stage)
    create_inactive_card(second_stage)

    errors = run_concurrently(
      -> { described_class.find(first_stage_cards.first.id).reorder_to_position!(kanban_stage: KanbanStage.find(second_stage.id), position: 1) },
      -> { described_class.find(second_stage_cards.first.id).reorder_to_position!(kanban_stage: KanbanStage.find(first_stage.id), position: 1) }
    )

    expect(errors).to be_empty
    expect_card_invariants
  end

  it 'keeps active positions stable when a cross-stage move races a manual top insert' do
    source_cards = create_cards(first_stage, 3)
    create_cards(second_stage, 3)
    create_inactive_card(second_stage)

    errors = run_concurrently(
      -> { described_class.find(source_cards.last.id).reorder_to_position!(kanban_stage: KanbanStage.find(second_stage.id), position: 1) },
      -> { create_manual_card('Concurrent manual opportunity') }
    )

    expect(errors).to be_empty
    expect_card_invariants
  end

  it 'keeps active positions stable when a cross-stage move races an automatic top insert' do
    source_cards = create_cards(first_stage, 3)
    create_cards(second_stage, 3)
    create_inactive_card(first_stage)
    conversation = create(:conversation, account: account, contact: contact, inbox: inbox)

    errors = run_concurrently(
      -> { described_class.find(source_cards.last.id).reorder_to_position!(kanban_stage: KanbanStage.find(second_stage.id), position: 1) },
      -> { KanbanCards::AutoCreateFromConversationService.new(Conversation.find(conversation.id)).perform! }
    )

    expect(errors).to be_empty
    expect(described_class.conversation.where(kanban_board: board, conversation: conversation).count).to eq(1)
    expect_card_invariants
  end

  it 'creates one manual card when concurrent creates use the same normalized subject' do
    create_cards(first_stage, 2)

    errors = run_concurrently(
      -> { create_manual_card('  Duplicate   Opportunity  ') },
      -> { create_manual_card('duplicate opportunity') }
    )

    expect(errors).to all(be_a(ActiveRecord::RecordInvalid)) unless errors.empty?
    expect(errors).not_to include(an_instance_of(ActiveRecord::RecordNotUnique))
    expect(
      described_class.manual.active.where(
        kanban_board: board, contact: contact, inbox: inbox, normalized_subject: 'duplicate opportunity'
      ).count
    ).to eq(1)
    expect_card_invariants
  end

  it 'creates one automatic card when concurrent creates use the same conversation' do
    create_cards(first_stage, 2)
    conversation = create(:conversation, account: account, contact: contact, inbox: inbox)

    errors = run_concurrently(
      -> { KanbanCards::AutoCreateFromConversationService.new(Conversation.find(conversation.id)).perform! },
      -> { KanbanCards::AutoCreateFromConversationService.new(Conversation.find(conversation.id)).perform! }
    )

    expect(errors).to be_empty
    expect(described_class.conversation.where(kanban_board: board, conversation: conversation).count).to eq(1)
    expect_card_invariants
  end

  it 'keeps active positions stable when delete races a reorder in the same stage' do
    cards = create_cards(first_stage, 5)
    lock_acquired = Queue.new

    errors = run_concurrently(
      lambda {
        described_class.transaction do
          described_class.lock_reorder_stages!([first_stage.id])
          described_class.lock_active_cards_for_stages!(board, [first_stage.id])
          lock_acquired << true
          sleep 0.2
          described_class.find(cards.last.id).reorder_to_position!(kanban_stage: KanbanStage.find(first_stage.id), position: 1)
        end
      },
      lambda {
        lock_acquired.pop
        described_class.find(cards.first.id).deactivate_and_normalize!
      }
    )

    expect(errors).to be_empty
    expect_card_invariants
  end

  it 'keeps active stage positions stable after concurrent stage reorder operations' do
    stages = [first_stage, second_stage, third_stage, create(:kanban_stage, account: account, kanban_board: board, position: 4)]
    create_cards(first_stage, 2)

    errors = run_concurrently(
      -> { reorder_stage_to_position(stages.first.id, 4) },
      -> { reorder_stage_to_position(stages.last.id, 1) }
    )

    expect(errors).to be_empty
    expect_stage_invariants
    expect_card_invariants
  end

  def create_cards(stage, count)
    Array.new(count) do |index|
      create(
        :kanban_card,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        contact: contact,
        inbox: inbox,
        subject: "Opportunity #{stage.id}-#{index}",
        position: index + 1
      )
    end
  end

  def create_inactive_card(stage)
    create(:kanban_card, account: account, kanban_board: board, kanban_stage: stage, contact: contact, inbox: inbox, position: 1, active: false)
  end

  def create_manual_card(subject)
    KanbanCards::CreateManualCardService.new(
      account: Account.find(account.id),
      user: User.find(user.id),
      kanban_board: KanbanBoard.find(board.id),
      kanban_stage: KanbanStage.find(first_stage.id),
      contact: Contact.find(contact.id),
      inbox: Inbox.find(inbox.id),
      subject: subject
    ).perform!
  end

  # rubocop:disable Metrics/AbcSize
  def reorder_stage_to_position(stage_id, target_position)
    KanbanStage.transaction do
      fresh_board = KanbanBoard.find(board.id)
      stage = KanbanStage.find(stage_id)

      KanbanStage.normalize_positions_for_board!(fresh_board)
      stage.reload

      ordered_stages = fresh_board.kanban_stages.active.ordered.to_a
      current_index = ordered_stages.index(stage)
      clamped_index = (target_position - 1).clamp(0, ordered_stages.length - 1)
      next if current_index.blank? || clamped_index == current_index

      ordered_stages.delete_at(current_index)
      ordered_stages.insert(clamped_index, stage)

      ordered_stages.each_with_index do |ordered_stage, index|
        ordered_stage.update!(position: index + 1) if ordered_stage.position != index + 1
      end

      KanbanStage.normalize_positions_for_board!(fresh_board)
    end
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/MethodLength
  def run_concurrently(*operations)
    barrier = concurrent_barrier(operations.length)
    errors = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          configure_connection_timeouts
          barrier.call
          operation.call
        ensure
          reset_connection_timeouts
        end
      rescue StandardError => e
        errors << e
      end
    end

    Timeout.timeout(thread_timeout) { threads.each(&:join) }
    drain_queue(errors)
  ensure
    threads&.each(&:kill)
    ActiveRecord::Base.connection_handler.clear_active_connections!
  end
  # rubocop:enable Metrics/MethodLength

  def concurrent_barrier(count)
    mutex = Mutex.new
    condition = ConditionVariable.new
    waiting = 0

    lambda do
      mutex.synchronize do
        waiting += 1
        condition.broadcast if waiting == count
        condition.wait(mutex) while waiting < count
      end
    end
  end

  def configure_connection_timeouts
    return unless postgresql?

    ActiveRecord::Base.connection.execute("SET statement_timeout = #{statement_timeout_ms}")
    ActiveRecord::Base.connection.execute("SET lock_timeout = #{lock_timeout_ms}")
  end

  def reset_connection_timeouts
    return unless postgresql?

    ActiveRecord::Base.connection.execute('RESET statement_timeout')
    ActiveRecord::Base.connection.execute('RESET lock_timeout')
  end

  def postgresql?
    ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
  end

  def drain_queue(queue)
    items = []
    items << queue.pop until queue.empty?
    items
  end

  # rubocop:disable Metrics/AbcSize
  def expect_card_invariants
    described_class.where(kanban_board: board).active.group_by(&:kanban_stage_id).each_value do |cards|
      positions = cards.sort_by { |card| [card.position, card.created_at, card.id] }.pluck(:position)

      expect(positions).to eq((1..positions.length).to_a)
      expect(positions.uniq.length).to eq(positions.length)
    end

    inactive_card_ids = described_class.where(kanban_board: board, active: false).pluck(:id)
    expect(described_class.active.where(id: inactive_card_ids)).to be_empty
    expect(described_class.active.joins(:kanban_stage).where(kanban_board: board, kanban_stages: { active: false })).to be_empty
  end
  # rubocop:enable Metrics/AbcSize

  def expect_stage_invariants
    positions = board.kanban_stages.active.ordered.pluck(:position)

    expect(positions).to eq((1..positions.length).to_a)
    expect(positions.uniq.length).to eq(positions.length)
  end

  def clean_database!
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.disable_referential_integrity do
        (connection.tables - %w[schema_migrations ar_internal_metadata]).each do |table|
          connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
        end
      end
    end
  end
end
