require 'rails_helper'

RSpec.describe KanbanAutomations::PurgeLogsJob, type: :job do
  it 'deletes expired logs and preserves recent logs' do
    expired_log = create(:kanban_automation_log, created_at: 91.days.ago)
    recent_log = create(:kanban_automation_log, created_at: 89.days.ago)

    described_class.perform_now

    expect(KanbanAutomationLog.exists?(expired_log.id)).to be(false)
    expect(KanbanAutomationLog.exists?(recent_log.id)).to be(true)
  end
end
