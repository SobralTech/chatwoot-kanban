class Api::V1::Widget::InboxMembersController < Api::V1::Widget::BaseController
  skip_before_action :set_contact

  def index
    @inbox_members = @web_widget.inbox.inbox_members.includes(user: { avatar_attachment: :blob }).to_a
    @account_users_by_user_id = AccountUser
                                .where(account_id: @current_account.id, user_id: @inbox_members.map(&:user_id))
                                .index_by(&:user_id)
  end
end
