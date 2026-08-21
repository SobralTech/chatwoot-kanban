# The Kanban automation endpoints answer 403 to an operator who may see a board but not
# manage its rules, where the rest of the API answers 401. S19 asks for the clearer
# status, and both automation controllers give the same answer, so it lives here.
#
# It has to be a rescue around the authorize call rather than a rescue_from: the global
# handler is an around_action, so it would catch Pundit::NotAuthorizedError first.
module KanbanAutomationAuthorization
  extend ActiveSupport::Concern

  private

  def with_automation_authorization
    yield
  rescue Pundit::NotAuthorizedError
    render json: { error: 'You are not authorized to do this action' }, status: :forbidden
  end
end
