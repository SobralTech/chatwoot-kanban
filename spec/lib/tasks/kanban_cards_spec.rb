require 'rails_helper'
require 'rake'

Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
load Rails.root.join('lib/tasks/kanban_cards.rake') unless Rake::Task.task_defined?('kanban_cards:backfill')

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe KanbanCardsBackfill do
  let(:task) { Rake::Task['kanban_cards:backfill'] }
  let(:batch_size) { '2' }

  after do
    task.reenable
  end

  describe 'valid legacy rows' do
    # rubocop:disable RSpec/MultipleExpectations
    it 'dry-runs, migrates valid rows in batches, and remains idempotent' do
      legacy_states = create_valid_legacy_states(count: 5)

      dry_run_output = run_task('DRY_RUN' => 'true', 'BATCH_SIZE' => batch_size)

      expect(KanbanCard.count).to eq(0)
      expect(dry_run_output).to include('scanned rows: 5')
      expect(dry_run_output).to include('eligible rows: 5')
      expect(dry_run_output).to include('inserted rows: 0')
      expect(dry_run_output).to include('dry-run status: true')

      first_run_output = run_task('BATCH_SIZE' => batch_size)

      expect(KanbanCard.count).to eq(5)
      expect(first_run_output).to include('scanned rows: 5')
      expect(first_run_output).to include('eligible rows: 5')
      expect(first_run_output).to include('inserted rows: 5')
      expect(first_run_output).to include('already migrated/conflicted rows: 0')
      expect(ConversationKanbanState.count).to eq(5)
      expect_migrated_cards_to_match(legacy_states)

      second_run_output = run_task('BATCH_SIZE' => batch_size)

      expect(KanbanCard.count).to eq(5)
      expect(second_run_output).to include('inserted rows: 0')
      expect(second_run_output).to include('already migrated/conflicted rows: 5')
    end
    # rubocop:enable RSpec/MultipleExpectations
  end

  describe 'conflicts' do
    it 'skips matching active automatic cards and continues' do
      legacy_state = create_valid_legacy_states(count: 1).first
      create(
        :kanban_card,
        :conversation_origin,
        account: legacy_state.conversation.account,
        kanban_board: legacy_state.kanban_board,
        kanban_stage: legacy_state.kanban_stage,
        conversation: legacy_state.conversation,
        position: 99
      )

      output = run_task('BATCH_SIZE' => batch_size)

      expect(KanbanCard.count).to eq(1)
      expect(output).to include('scanned rows: 1')
      expect(output).to include('eligible rows: 1')
      expect(output).to include('inserted rows: 0')
      expect(output).to include('already migrated/conflicted rows: 1')
    end
  end

  describe 'invalid rows' do
    # rubocop:disable RSpec/MultipleExpectations
    it 'groups safely representable invalid legacy rows by skip reason' do
      create_invalid_legacy_rows

      output = run_task('BATCH_SIZE' => batch_size)

      expect(KanbanCard.count).to eq(0)
      expect(output).to include('scanned rows: 6')
      expect(output).to include('eligible rows: 0')
      expect(output).to include('inserted rows: 0')
      expect(output).to include('skipped rows: 6')
      expect(output).to include('missing_conversation: 1')
      expect(output).to include('missing_contact: 1')
      expect(output).to include('missing_board: 1')
      expect(output).to include('missing_stage: 1')
      expect(output).to include('account_mismatch: 1')
      expect(output).to include('stage_board_mismatch: 1')
    end
    # rubocop:enable RSpec/MultipleExpectations
  end

  private

  def run_task(env)
    output = nil

    with_modified_env(env) do
      output = capture_stdout { task.invoke }
    end

    task.reenable
    output
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def create_valid_legacy_states(count:)
    account = create(:account)
    board = create(:kanban_board, account: account)
    stage = create(:kanban_stage, account: account, kanban_board: board)

    Array.new(count) do |index|
      conversation = create(:conversation, account: account)
      timestamp = (index + 1).days.ago.change(usec: 0)
      create(
        :conversation_kanban_state,
        account: account,
        kanban_board: board,
        kanban_stage: stage,
        conversation: conversation,
        position: index + 1,
        created_at: timestamp,
        updated_at: timestamp
      )
    end
  end

  def expect_migrated_cards_to_match(legacy_states)
    legacy_states.each do |state|
      card = KanbanCard.find_by!(kanban_board: state.kanban_board, conversation: state.conversation)

      expect_migrated_card_associations(card, state)
      expect_migrated_card_attributes(card, state)
    end
  end

  def expect_migrated_card_associations(card, state)
    aggregate_failures do
      expect(card.account_id).to eq(state.conversation.account_id)
      expect(card.kanban_stage_id).to eq(state.kanban_stage_id)
      expect(card.contact_id).to eq(state.conversation.contact_id)
      expect(card.inbox_id).to eq(state.conversation.inbox_id)
    end
  end

  def expect_migrated_card_attributes(card, state)
    aggregate_failures do
      expect(card.position).to eq(state.position)
      expect(card.created_at.to_i).to eq(state.created_at.to_i)
      expect(card.updated_at.to_i).to eq(state.updated_at.to_i)
    end

    expect_migrated_card_defaults(card)
  end

  def expect_migrated_card_defaults(card)
    aggregate_failures do
      expect(card.origin).to eq('conversation')
      expect(card.subject).to be_nil
      expect(card.normalized_subject).to be_nil
      expect(card).to be_active
    end
  end

  def create_invalid_legacy_rows
    account = create(:account)
    board = create(:kanban_board, account: account)
    stage = create(:kanban_stage, account: account, kanban_board: board)

    create_missing_conversation_state(account, board, stage)
    create_missing_contact_state(account, board, stage)
    create_missing_board_state(account, stage)
    create_missing_stage_state(account, board)
    create_account_mismatch_state
    create_stage_board_mismatch_state(account)
  end

  def create_missing_conversation_state(account, board, stage)
    insert_legacy_state(account_id: account.id, conversation_id: missing_id, kanban_board_id: board.id, kanban_stage_id: stage.id)
  end

  def create_missing_contact_state(account, board, stage)
    conversation = create(:conversation, account: account)
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:contact_id, nil)
    # rubocop:enable Rails/SkipsModelValidations
    insert_legacy_state(account_id: account.id, conversation_id: conversation.id, kanban_board_id: board.id, kanban_stage_id: stage.id)
  end

  def create_missing_board_state(account, stage)
    conversation = create(:conversation, account: account)

    insert_legacy_state(account_id: account.id, conversation_id: conversation.id, kanban_board_id: missing_id, kanban_stage_id: stage.id)
  end

  def create_missing_stage_state(account, board)
    conversation = create(:conversation, account: account)

    insert_legacy_state(account_id: account.id, conversation_id: conversation.id, kanban_board_id: board.id, kanban_stage_id: missing_id)
  end

  def create_account_mismatch_state
    conversation = create(:conversation)
    other_account = create(:account)
    other_board = create(:kanban_board, account: other_account)
    other_stage = create(:kanban_stage, account: other_account, kanban_board: other_board)

    insert_legacy_state(
      account_id: other_account.id,
      conversation_id: conversation.id,
      kanban_board_id: other_board.id,
      kanban_stage_id: other_stage.id
    )
  end

  def create_stage_board_mismatch_state(account)
    conversation = create(:conversation, account: account)
    board = create(:kanban_board, account: account)
    other_board = create(:kanban_board, account: account)
    other_stage = create(:kanban_stage, account: account, kanban_board: other_board)

    insert_legacy_state(account_id: account.id, conversation_id: conversation.id, kanban_board_id: board.id, kanban_stage_id: other_stage.id)
  end

  def insert_legacy_state(attributes)
    # rubocop:disable Rails/SkipsModelValidations
    ConversationKanbanState.insert!(
      attributes.merge(position: 1, created_at: Time.current, updated_at: Time.current)
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def missing_id
    999_999_999
  end
end

RSpec.describe KanbanCardsParityAudit do
  let(:task) { Rake::Task['kanban_cards:audit_parity'] }

  after do
    task.reenable
  end

  describe '#run' do
    it 'reports clean parity for an empty database' do
      output = run_audit

      expect(output).to include('legacy_rows: 0')
      expect(output).to include('matching_rows: 0')
      expect(output).to include('missing_mirror: 0')
      expect(output).to include('field_mismatch: 0')
      expect(output).to include('standalone_conversation_cards: 0')
    end

    it 'reports clean parity for matching legacy and mirror rows with nil subject' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state, subject: nil)

      output = run_audit

      expect(output).to include('legacy_rows: 1')
      expect(output).to include('matching_rows: 1')
      expect(output).to include('missing_mirror: 0')
      expect(output).to include('field_mismatch: 0')
    end

    it 'reports clean parity for matching conversation-origin mirrors with generated subjects' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state, subject: 'Lead [Maria da Silva] - [WhatsApp Comercial]')

      output = run_audit

      expect(output).to include('legacy_rows: 1')
      expect(output).to include('matching_rows: 1')
      expect(output).to include('field_mismatch: 0')
      expect(output).not_to include('  subject:')
    end

    it 'detects a missing mirror' do
      create_valid_legacy_state

      output = run_audit

      expect(output).to include('legacy_rows: 1')
      expect(output).to include('matching_rows: 0')
      expect(output).to include('missing_mirror: 1')
    end

    it 'detects a field mismatch and groups it by field' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state, position: legacy_state.position + 1)

      output = run_audit

      expect(output).to include('field_mismatch: 1')
      expect(output).to include('  position: 1')
    end

    it 'detects stage drift and groups it by field' do
      legacy_state = create_valid_legacy_state
      other_stage = create(:kanban_stage, account: legacy_state.account, kanban_board: legacy_state.kanban_board)
      create_matching_mirror(legacy_state, kanban_stage: other_stage)

      output = run_audit

      expect(output).to include('field_mismatch: 1')
      expect(output).to include('  kanban_stage_id: 1')
    end

    it 'detects non-null normalized subject and groups it by field' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state, subject: 'Lead [Maria da Silva] - [WhatsApp Comercial]')
      KanbanCard.last.update_column(:normalized_subject, 'lead maria') # rubocop:disable Rails/SkipsModelValidations

      output = run_audit
      expect(output).to include('field_mismatch: 1')
      expect(output).to include('  normalized_subject: 1')
    end

    it 'detects an inactive mirror for an active legacy row' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state, active: false)

      output = run_audit

      expect(output).to include('inactive_mirror_for_active_legacy: 1')
      expect(output).to include('field_mismatch: 1')
      expect(output).to include('  active: 1')
    end

    it 'reports a standalone automatic conversation card' do
      create(:kanban_card, :conversation_origin)

      output = run_audit

      expect(output).to include('legacy_rows: 0')
      expect(output).to include('standalone_conversation_cards: 1')
    end

    it 'returns success when only standalone automatic conversation cards exist' do
      create(:kanban_card, :conversation_origin)

      capture_stdout do
        expect(described_class.new.run).to be(true)
      end
    end

    it 'ignores manual cards' do
      create(:kanban_card)

      output = run_audit

      expect(output).to include('legacy_rows: 0')
      expect(output).to include('standalone_conversation_cards: 0')
    end

    it 'returns success for a clean audit' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state)

      capture_stdout do
        expect(described_class.new.run).to be(true)
      end
    end
  end

  describe 'rake task exit status' do
    it 'returns non-zero exit status when drift exists' do
      create_valid_legacy_state

      expect { capture_stdout { task.invoke } }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end

    it 'returns success when the audit is clean' do
      legacy_state = create_valid_legacy_state
      create_matching_mirror(legacy_state)

      expect { capture_stdout { task.invoke } }.not_to raise_error
    end

    it 'returns success when only standalone automatic conversation cards exist' do
      create(:kanban_card, :conversation_origin)

      expect { capture_stdout { task.invoke } }.not_to raise_error
    end
  end

  private

  def run_audit
    capture_stdout { described_class.new.run }
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def create_valid_legacy_state
    account = create(:account)
    board = create(:kanban_board, account: account)
    stage = create(:kanban_stage, account: account, kanban_board: board)
    conversation = create(:conversation, account: account)

    create(
      :conversation_kanban_state,
      account: account,
      conversation: conversation,
      kanban_board: board,
      kanban_stage: stage,
      position: 1
    )
  end

  def create_matching_mirror(legacy_state, attributes = {})
    create(
      :kanban_card,
      :conversation_origin,
      {
        account: legacy_state.conversation.account,
        kanban_board: legacy_state.kanban_board,
        kanban_stage: legacy_state.kanban_stage,
        conversation: legacy_state.conversation,
        position: legacy_state.position
      }.merge(attributes)
    )
  end
end
# rubocop:enable RSpec/MultipleDescribes
