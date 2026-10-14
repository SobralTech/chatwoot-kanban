class ConversationFinder # rubocop:disable Metrics/ClassLength
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  UNASSIGNED_CONDITION = Conversation.arel_table[:assignee_id].eq(nil).and(Conversation.arel_table[:assignee_agent_bot_id].eq(nil))
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {open: count, resolved: count}}

  # params
  # assignee_type, inbox_id, :status

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = current_account.account_users.find_by(user_id: current_user.id)&.administrator?
    @params = params
  end

  def perform
    set_up

    count_base = @conversations
    apply_all_conversations_inbox_visibility
    list_base = @conversations

    counts = conversation_counts(count_base, list_base)

    filter_by_assignee_type

    {
      conversations: conversations,
      count: {
        mine_count: counts.fetch(:mine),
        assigned_count: counts.fetch(:assigned),
        unassigned_count: counts.fetch(:unassigned),
        all_count: counts.fetch(:all)
      }
    }
  end

  def perform_meta_only
    set_up

    count_base = @conversations
    apply_all_conversations_inbox_visibility
    list_base = @conversations

    counts = conversation_counts(count_base, list_base)

    {
      count: {
        mine_count: counts.fetch(:mine),
        assigned_count: counts.fetch(:assigned),
        unassigned_count: counts.fetch(:unassigned),
        all_count: counts.fetch(:all)
      }
    }
  end

  private

  def conversation_counts(count_base, list_base)
    table = Conversation.arel_table
    total, unassigned, mine = count_relation(count_base).pick(
      table[:id].count,
      table[:id].count.filter(UNASSIGNED_CONDITION),
      table[:id].count.filter(table[:assignee_id].eq(current_user.id))
    )

    {
      mine: mine.to_i,
      assigned: total.to_i - unassigned.to_i,
      unassigned: unassigned.to_i,
      all: all_conversations_view? ? list_base.count : total.to_i
    }
  end

  # Keeping the original relation as a derived table preserves whether its joins
  # intentionally produce duplicates and whether a filter added DISTINCT.
  def count_relation(scope)
    selected_scope = scope.reorder(nil).reselect(:id, :assignee_id, :assignee_agent_bot_id)
    Conversation.from("(#{selected_scope.to_sql}) conversations")
  end

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    filter_by_status unless params[:q]
    filter_by_team
    filter_by_labels
    filter_by_query
    filter_by_source_id
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id])
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    @team = current_account.teams.find(params[:team_id]) if params[:team_id]
  end

  def find_conversation_by_inbox
    @conversations = current_account.conversations

    return unless params[:inbox_id]

    @conversations = @conversations.where(inbox_id: @inbox_ids)
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform

    if params[:conversation_type] == 'archived'
      @conversations = @conversations.archived
    else
      @conversations = @conversations.not_archived
      filter_by_conversation_type if params[:conversation_type]
    end

    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned
    when 'assigned'
      @conversations = @conversations.assigned
    end
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      conversation_ids = current_account.mentions.where(user: current_user).pluck(:conversation_id)
      @conversations = @conversations.where(id: conversation_ids)
    when 'participating'
      participant_conversation_ids = ConversationParticipant.where(account_id: current_account.id, user_id: current_user.id).select(:conversation_id)
      @conversations = @conversations.where(id: participant_conversation_ids)
    when 'unattended'
      @conversations = @conversations.unattended
    when 'email'
      @conversations = @conversations.joins(:inbox).where(inboxes: { channel_type: 'Channel::Email' })
    end
    @conversations
  end

  def filter_by_query
    return unless params[:q]

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    @conversations = conversations.joins(:messages).where('unaccent(messages.content) ILIKE unaccent(:search)', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types })
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team

    @conversations = @conversations.where(team: @team)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  def all_conversations_view?
    params[:conversation_view] == 'all' && params[:inbox_id].blank?
  end

  def apply_all_conversations_inbox_visibility
    return unless all_conversations_view?

    @conversations = @conversations.joins(:inbox).where(inboxes: { show_in_all_conversations: true })
  end

  def current_page
    params[:page] || 1
  end

  def conversations_base_query
    @conversations.includes(
      :taggings, :team, :contact_inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }
    ).preload(inbox: :channel, ai_assignee: { avatar_attachment: [:blob] })
  end

  # Some filters may use a plain SELECT DISTINCT, which Postgres forbids
  # combining with an ORDER BY on a joined column (conversation_pins.pinned_at)
  # that isn't in the select list. Collapsing to an id subquery gives
  # pinned_first a clean relation to order, but it forces a full table scan,
  # so only pay for it when DISTINCT is present.
  def drop_distinct_for_ordering
    return unless @conversations.distinct_value

    @conversations = Conversation.where(id: @conversations.reselect(:id))
  end

  def conversations
    drop_distinct_for_ordering
    @conversations = Conversations::SortService.apply(conversations_base_query.pinned_first, params[:sort_by])

    if params[:updated_within].present?
      @conversations.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
    else
      @conversations.page(current_page).per(ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i)
    end
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
