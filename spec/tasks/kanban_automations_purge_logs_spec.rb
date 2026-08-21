require 'rails_helper'
require 'rake'

Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
load Rails.root.join('lib/tasks/kanban_automations.rake') unless Rake::Task.task_defined?('kanban_automations:purge_logs')

RSpec.describe 'kanban automation log purge task', type: :task do
  let(:task) { Rake::Task['kanban_automations:purge_logs'] }

  before do
    task.reenable
  end

  it 'deletes logs older than 90 days and keeps newer logs' do
    old_log = create(:kanban_automation_log, created_at: 91.days.ago)
    recent_log = create(:kanban_automation_log, created_at: 89.days.ago)

    task.invoke

    expect(KanbanAutomationLog.exists?(old_log.id)).to be(false)
    expect(KanbanAutomationLog.exists?(recent_log.id)).to be(true)
  end
end
