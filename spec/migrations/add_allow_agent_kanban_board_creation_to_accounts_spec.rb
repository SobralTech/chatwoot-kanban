require 'rails_helper'
require Rails.root.join('db/migrate/20260613120000_add_allow_agent_kanban_board_creation_to_accounts')

RSpec.describe AddAllowAgentKanbanBoardCreationToAccounts do
  subject(:migration) { described_class.new }

  after do
    migration.migrate(:up) unless column_exists?
  end

  it 'is reversible with a true default' do
    migration.migrate(:down)
    expect(column_exists?).to be(false)

    migration.migrate(:up)
    expect(column_exists?).to be(true)

    column = ActiveRecord::Base.connection.columns(:accounts).find { |account_column| account_column.name == 'allow_agent_kanban_board_creation' }
    expect(column.default).to eq('true')
    expect(column.null).to be(false)
  end

  def column_exists?
    ActiveRecord::Base.connection.column_exists?(:accounts, :allow_agent_kanban_board_creation)
  end
end
