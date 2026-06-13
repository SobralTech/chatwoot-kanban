require 'rails_helper'

RSpec.describe 'Kanban board routes', type: :routing do
  it 'does not route account-level settings through kanban board show' do
    expect(get: '/api/v1/accounts/1/kanban_boards/settings').not_to be_routable
  end

  it 'does not route account-level settings updates' do
    expect(patch: '/api/v1/accounts/1/kanban_boards/settings').not_to be_routable
  end
end
