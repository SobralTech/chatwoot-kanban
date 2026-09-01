class Api::V1::Accounts::AssignmentPoliciesController < Api::V1::Accounts::BaseController
  before_action :fetch_assignment_policy, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @assignment_policies = Current.account.assignment_policies.to_a
    @assigned_inbox_counts = InboxAssignmentPolicy
                             .where(assignment_policy_id: @assignment_policies.map(&:id))
                             .group(:assignment_policy_id)
                             .count
  end

  def show; end

  def create
    @assignment_policy = Current.account.assignment_policies.create!(assignment_policy_params)
  end

  def update
    @assignment_policy.update!(assignment_policy_params)
  end

  def destroy
    @assignment_policy.destroy!
    head :ok
  end

  private

  def fetch_assignment_policy
    @assignment_policy = Current.account.assignment_policies.find(params[:id])
  end

  def assignment_policy_params
    params.require(:assignment_policy).permit(
      :name, :description, :assignment_order, :conversation_priority,
      :fair_distribution_limit, :fair_distribution_window, :enabled
    )
  end
end
