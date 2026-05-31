require 'rails_helper'
require 'rake'

Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
load Rails.root.join('lib/tasks/kanban_boards.rake') unless Rake::Task.task_defined?('kanban_boards:backfill_default_stages')

RSpec.describe KanbanBoardsDefaultStagesBackfill do # rubocop:disable RSpec/SpecFilePathFormat
  let(:task) { Rake::Task['kanban_boards:backfill_default_stages'] }

  after do
    task.reenable
  end

  it 'dry-runs eligible boards without updating them' do
    board = create_board_with_stage

    output = run_task('DRY_RUN' => 'true')

    expect(board.reload.default_stage_id).to be_nil
    expect(output).to include('eligible_boards: 1')
    expect(output).to include('updated_boards: 0')
    expect(output).to include('dry_run: true')
  end

  it 'assigns the first active stage on a real run' do
    board = create(:kanban_board)
    stage = create(:kanban_stage, account: board.account, kanban_board: board)

    output = run_task

    expect(board.reload.default_stage_id).to eq(stage.id)
    expect(output).to include('updated_boards: 1')
  end

  it 'orders stages by position, created_at, and id' do
    board = create(:kanban_board)
    timestamp = 3.days.ago.change(usec: 0)
    create(:kanban_stage, account: board.account, kanban_board: board, position: 2, created_at: timestamp - 1.day)
    default_stage = create(:kanban_stage, account: board.account, kanban_board: board, position: 1, created_at: timestamp)
    create(:kanban_stage, account: board.account, kanban_board: board, position: 1, created_at: timestamp)
    create(:kanban_stage, account: board.account, kanban_board: board, position: 1, created_at: timestamp + 1.day)

    run_task

    expect(board.reload.default_stage_id).to eq(default_stage.id)
  end

  it 'is idempotent on second execution' do
    board = create_board_with_stage

    first_output = run_task
    second_output = run_task

    expect(board.reload.default_stage_id).to be_present
    expect(first_output).to include('updated_boards: 1')
    expect(second_output).to include('updated_boards: 0')
    expect(second_output).to include('already_configured_boards: 1')
  end

  it 'preserves an existing valid default stage' do
    board = create(:kanban_board)
    default_stage = create(:kanban_stage, account: board.account, kanban_board: board, position: 2)
    create(:kanban_stage, account: board.account, kanban_board: board, position: 1)
    board.update!(default_stage: default_stage)

    output = run_task

    expect(board.reload.default_stage_id).to eq(default_stage.id)
    expect(output).to include('already_configured_boards: 1')
    expect(output).to include('updated_boards: 0')
  end

  it 'ignores inactive boards' do
    board = create(:kanban_board, active: false)
    create(:kanban_stage, account: board.account, kanban_board: board)

    output = run_task

    expect(board.reload.default_stage_id).to be_nil
    expect(output).to include('skipped_inactive_boards: 1')
    expect(output).to include('updated_boards: 0')
  end

  it 'skips boards without an active stage' do
    board = create(:kanban_board)

    output = run_task

    expect(board.reload.default_stage_id).to be_nil
    expect(output).to include('eligible_boards: 1')
    expect(output).to include('skipped_without_active_stage: 1')
    expect(output).to include('updated_boards: 0')
  end

  it 'ignores inactive stages' do
    board = create(:kanban_board)
    create(:kanban_stage, account: board.account, kanban_board: board, position: 1, active: false)
    active_stage = create(:kanban_stage, account: board.account, kanban_board: board, position: 2)

    run_task

    expect(board.reload.default_stage_id).to eq(active_stage.id)
  end

  it 'processes multiple boards with BATCH_SIZE=2' do
    boards = Array.new(5) { create_board_with_stage }

    output = run_task('BATCH_SIZE' => '2')

    expect(boards.map { |board| board.reload.default_stage_id }).to all(be_present)
    expect(output).to include('scanned_boards: 5')
    expect(output).to include('eligible_boards: 5')
    expect(output).to include('updated_boards: 5')
    expect(output).to include('batch_size: 2')
  end

  private

  def run_task(env = {})
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

  def create_board_with_stage
    board = create(:kanban_board)
    create(:kanban_stage, account: board.account, kanban_board: board)
    board
  end
end
