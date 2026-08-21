require 'rails_helper'

RSpec.describe KanbanAutomationLog do
  it 'accepts the supported statuses' do
    log = build(:kanban_automation_log, status: 'simulated')

    expect(log).to be_valid
  end

  it 'rejects unknown statuses' do
    log = build(:kanban_automation_log, status: 'unknown')

    expect(log).not_to be_valid
    expect(log.errors[:status]).to be_present
  end
end
